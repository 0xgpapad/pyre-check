(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Core
open Pyre
open Taint
module Target = Interprocedural.Target

(* Registers the Taint analysis with the interprocedural analysis framework. *)
include Taint.Result.Register (struct
  include Taint.Result

  let initialize_configuration
      ~static_analysis_configuration:
        { Configuration.StaticAnalysis.configuration = { taint_model_paths; _ }; _ }
    =
    (* In order to save time, sanity check models before starting the analysis. *)
    Log.info "Verifying model syntax and configuration.";
    let timer = Timer.start () in
    Taint.Model.get_model_sources ~paths:taint_model_paths
    |> List.iter ~f:(fun (path, source) -> Taint.Model.verify_model_syntax ~path ~source);
    let (_ : Taint.TaintConfiguration.t) =
      Taint.TaintConfiguration.create
        ~rule_filter:None
        ~find_missing_flows:None
        ~dump_model_query_results_path:None
        ~maximum_trace_length:None
        ~maximum_tito_depth:None
        ~taint_model_paths
    in
    Statistics.performance
      ~name:"Verified model syntax and configuration"
      ~phase_name:"Verifying model syntax and configuration"
      ~timer
      ()


  let log_and_reraise_taint_model_exception exception_ =
    Log.error "Error getting taint models.";
    Log.error "%s" (Exn.to_string exception_);
    raise exception_


  type model_query_data = {
    queries: Model.ModelQuery.rule list;
    taint_configuration: TaintConfiguration.t;
  }

  type parse_sources_result = {
    initialize_result:
      call_model Interprocedural.AnalysisResult.InitializedModels.initialize_result;
    query_data: model_query_data option;
  }

  let generate_models_from_queries
      ~scheduler
      ~static_analysis_configuration:
        { Configuration.StaticAnalysis.rule_filter; find_missing_flows; _ }
      ~environment
      ~callables
      ~stubs
      ~initialize_result:
        { Interprocedural.AnalysisResult.InitializedModels.initial_models = models; skip_overrides }
      { queries; taint_configuration }
    =
    let resolution =
      Analysis.TypeCheck.resolution
        (Analysis.TypeEnvironment.ReadOnly.global_resolution environment)
        (* TODO(T65923817): Eliminate the need of creating a dummy context here *)
        (module Analysis.TypeCheck.DummyContext)
    in
    try
      let models =
        let callables =
          Hash_set.fold stubs ~f:(Core.Fn.flip List.cons) ~init:callables
          |> List.filter_map ~f:(function
                 | `Function _ as callable -> Some (callable :> Target.callable_t)
                 | `Method _ as callable -> Some (callable :> Target.callable_t)
                 | _ -> None)
        in
        TaintModelQuery.ModelQuery.apply_all_rules
          ~resolution
          ~scheduler
          ~configuration:taint_configuration
          ~rule_filter
          ~rules:queries
          ~callables
          ~stubs
          ~environment
          ~models
      in
      let remove_sinks models = Target.Map.map ~f:Model.remove_sinks models in
      let add_obscure_sinks models =
        let add_obscure_sink models callable =
          let model =
            Target.Map.find models callable
            |> Option.value ~default:Taint.Result.empty_model
            |> Model.add_obscure_sink ~resolution ~call_target:callable
            |> Model.remove_obscureness
          in
          Target.Map.set models ~key:callable ~data:model
        in
        stubs
        |> Hash_set.filter ~f:(fun callable ->
               Target.Map.find models callable >>| Model.is_obscure |> Option.value ~default:true)
        |> Hash_set.fold ~f:add_obscure_sink ~init:models
      in
      let find_missing_flows =
        find_missing_flows >>= TaintConfiguration.missing_flows_kind_from_string
      in
      let models =
        match find_missing_flows with
        | Some Obscure -> models |> remove_sinks |> add_obscure_sinks
        | Some Type -> models |> remove_sinks
        | None -> models
      in
      { Interprocedural.AnalysisResult.InitializedModels.initial_models = models; skip_overrides }
    with
    | exception_ -> log_and_reraise_taint_model_exception exception_


  let parse_models_and_queries_from_sources
      ~scheduler
      ~static_analysis_configuration:
        {
          Configuration.StaticAnalysis.verify_models;
          configuration = { taint_model_paths; _ };
          rule_filter;
          find_missing_flows;
          dump_model_query_results;
          maximum_trace_length;
          maximum_tito_depth;
          _;
        }
      ~environment
      ~callables
      ~stubs
    =
    let resolution =
      Analysis.TypeCheck.resolution
        (Analysis.TypeEnvironment.ReadOnly.global_resolution environment)
        (* TODO(T65923817): Eliminate the need of creating a dummy context here *)
        (module Analysis.TypeCheck.DummyContext)
    in
    let create_models ~taint_configuration ~initial_models sources =
      let map state sources =
        List.fold
          sources
          ~init:state
          ~f:(fun (models, errors, skip_overrides, queries) (path, source) ->
            let {
              ModelParser.T.models;
              errors = new_errors;
              skip_overrides = new_skip_overrides;
              queries = new_queries;
            }
              =
              ModelParser.parse
                ~resolution
                ~path
                ~source
                ~configuration:taint_configuration
                ~callables
                ~stubs
                ?rule_filter
                models
            in
            ( models,
              List.rev_append new_errors errors,
              Set.union skip_overrides new_skip_overrides,
              List.rev_append new_queries queries ))
      in
      let reduce
          (models_left, errors_left, skip_overrides_left, queries_left)
          (models_right, errors_right, skip_overrides_right, queries_right)
        =
        let merge_models ~key:_ = function
          | `Left model
          | `Right model ->
              Some model
          | `Both (left, right) -> Some (Result.join ~iteration:0 left right)
        in
        ( Target.Map.merge models_left models_right ~f:merge_models,
          List.rev_append errors_left errors_right,
          Set.union skip_overrides_left skip_overrides_right,
          List.rev_append queries_left queries_right )
      in
      Scheduler.map_reduce
        scheduler
        ~policy:(Scheduler.Policy.legacy_fixed_chunk_count ())
        ~initial:(initial_models, [], Ast.Reference.Set.empty, [])
        ~map
        ~reduce
        ~inputs:sources
        ()
    in
    let add_models_and_queries_from_sources initial_models =
      try
        let find_missing_flows =
          find_missing_flows >>= TaintConfiguration.missing_flows_kind_from_string
        in
        let taint_configuration =
          TaintConfiguration.create
            ~rule_filter
            ~find_missing_flows
            ~dump_model_query_results_path:dump_model_query_results
            ~maximum_trace_length
            ~maximum_tito_depth
            ~taint_model_paths
        in
        TaintConfiguration.register taint_configuration;
        let models, errors, skip_overrides, queries =
          Model.get_model_sources ~paths:taint_model_paths
          |> create_models ~taint_configuration ~initial_models
        in
        Model.register_verification_errors errors;
        let () =
          if not (List.is_empty errors) then
            (* Exit or log errors, depending on whether models need to be verified. *)
            if not verify_models then begin
              Log.error "Found %d model verification errors!" (List.length errors);
              List.iter errors ~f:(fun error ->
                  Log.error "%s" (Taint.Model.display_verification_error error))
            end
            else begin
              Yojson.Safe.pretty_to_string
                (`Assoc
                  ["errors", `List (List.map errors ~f:Taint.Model.verification_error_to_json)])
              |> Log.print "%s";
              exit 0
            end
        in
        {
          initialize_result =
            {
              Interprocedural.AnalysisResult.InitializedModels.initial_models = models;
              skip_overrides;
            };
          query_data = Some { queries; taint_configuration };
        }
      with
      | exception_ -> log_and_reraise_taint_model_exception exception_
    in
    let initial_models = Model.infer_class_models ~environment in
    match taint_model_paths with
    | [] ->
        {
          initialize_result =
            {
              Interprocedural.AnalysisResult.InitializedModels.initial_models;
              skip_overrides = Ast.Reference.Set.empty;
            };
          query_data = None;
        }
    | _ -> add_models_and_queries_from_sources initial_models


  let initialize_models ~scheduler ~static_analysis_configuration ~environment ~callables ~stubs =
    let callables = (callables :> Target.t list) in
    let stubs = Target.HashSet.of_list (stubs :> Target.t list) in

    Log.info "Parsing taint models...";
    let timer = Timer.start () in
    let { initialize_result; query_data } =
      parse_models_and_queries_from_sources
        ~scheduler
        ~static_analysis_configuration
        ~environment
        ~callables:(Some (Target.HashSet.of_list callables))
        ~stubs
    in
    Statistics.performance ~name:"Parsed taint models" ~phase_name:"Parsing taint models" ~timer ();

    let get_taint_models ~updated_environment =
      match updated_environment, query_data with
      | Some updated_environment, Some query_data ->
          Log.info "Generating models from model queries...";
          let timer = Timer.start () in
          let models =
            generate_models_from_queries
              ~scheduler
              ~static_analysis_configuration
              ~environment:updated_environment
              ~callables
              ~stubs
              ~initialize_result
              query_data
          in
          Statistics.performance
            ~name:"Generated models from model queries"
            ~phase_name:"Generating models from model queries"
            ~timer
            ();
          models
      | _ -> initialize_result
    in
    Interprocedural.AnalysisResult.InitializedModels.create get_taint_models


  let apply_sanitizers
      {
        forward = { source_taint };
        backward = { taint_in_taint_out; sink_taint };
        sanitizers = { global; parameters; roots } as sanitizers;
        modes;
      }
    =
    let open Domains in
    let kinds_to_sanitize_transforms ~sources ~sinks =
      let source_transforms = Sources.Set.to_sanitize_transforms_exn sources in
      let sink_transforms = Sinks.Set.to_sanitize_transforms_exn sinks in
      SanitizeTransform.Set.union source_transforms sink_transforms
    in
    let sanitize_tito ?(sources = Sources.Set.empty) ?(sinks = Sinks.Set.empty) taint_in_taint_out =
      let transforms = kinds_to_sanitize_transforms ~sources ~sinks in
      BackwardState.apply_sanitize_transforms transforms taint_in_taint_out
    in
    let sanitize_tito_parameter
        parameter
        ?(sources = Sources.Set.empty)
        ?(sinks = Sinks.Set.empty)
        taint_in_taint_out
      =
      let sanitize_tito_taint_tree = function
        | None -> BackwardState.Tree.bottom
        | Some taint_tree ->
            let transforms = kinds_to_sanitize_transforms ~sources ~sinks in
            BackwardState.Tree.apply_sanitize_transforms transforms taint_tree
      in
      BackwardState.update taint_in_taint_out parameter ~f:sanitize_tito_taint_tree
    in

    (* Apply the global sanitizer. *)
    (* Here, we are applying the legacy behavior of sanitizers, where we only
     * sanitize the forward trace or the backward trace. *)
    let source_taint =
      (* @Sanitize(TaintSource[...]) *)
      match global.sources with
      | Some Sanitize.AllSources -> ForwardState.empty
      | Some (Sanitize.SpecificSources sanitized_sources) ->
          ForwardState.sanitize sanitized_sources source_taint
      | None -> source_taint
    in
    let taint_in_taint_out =
      (* @Sanitize(TaintInTaintOut[...]) *)
      match global.tito with
      | Some AllTito -> BackwardState.empty
      | Some (SpecificTito { sanitized_tito_sources; sanitized_tito_sinks }) ->
          sanitize_tito
            ~sources:sanitized_tito_sources
            ~sinks:sanitized_tito_sinks
            taint_in_taint_out
      | None -> taint_in_taint_out
    in
    let sink_taint =
      (* @Sanitize(TaintSink[...]) *)
      match global.sinks with
      | Some Sanitize.AllSinks -> BackwardState.empty
      | Some (Sanitize.SpecificSinks sanitized_sinks) ->
          BackwardState.sanitize sanitized_sinks sink_taint
      | None -> sink_taint
    in

    (* Apply the parameters sanitizer. *)
    (* Here, we apply sanitizers both in the forward and backward trace. *)
    (* Note that by design, sanitizing a specific source or sink also sanitizes
     * taint-in-taint-out for that source/sink. *)
    let sink_taint, taint_in_taint_out =
      (* Sanitize(Parameters[TaintSource[...]]) *)
      match parameters.sources with
      | Some Sanitize.AllSources -> sink_taint, taint_in_taint_out
      | Some (Sanitize.SpecificSources sanitized_sources) ->
          let sanitized_sources_transforms =
            Sources.Set.to_sanitize_transforms_exn sanitized_sources
          in
          let sink_taint =
            sink_taint
            |> BackwardState.apply_sanitize_transforms sanitized_sources_transforms
            |> BackwardState.transform BackwardTaint.kind Filter ~f:Flow.sink_can_match_rule
          in
          let taint_in_taint_out = sanitize_tito ~sources:sanitized_sources taint_in_taint_out in
          sink_taint, taint_in_taint_out
      | None -> sink_taint, taint_in_taint_out
    in
    let taint_in_taint_out =
      (* Sanitize(Parameters[TaintInTaintOut[...]]) *)
      match parameters.tito with
      | Some AllTito -> BackwardState.empty
      | Some (SpecificTito { sanitized_tito_sources; sanitized_tito_sinks }) ->
          sanitize_tito
            ~sources:sanitized_tito_sources
            ~sinks:sanitized_tito_sinks
            taint_in_taint_out
      | _ -> taint_in_taint_out
    in
    let sink_taint, taint_in_taint_out =
      (* Sanitize(Parameters[TaintSink[...]]) *)
      match parameters.sinks with
      | Some Sanitize.AllSinks ->
          let sink_taint = BackwardState.empty in
          sink_taint, taint_in_taint_out
      | Some (Sanitize.SpecificSinks sanitized_sinks) ->
          let sink_taint = BackwardState.sanitize sanitized_sinks sink_taint in
          let taint_in_taint_out = sanitize_tito ~sinks:sanitized_sinks taint_in_taint_out in
          sink_taint, taint_in_taint_out
      | None -> sink_taint, taint_in_taint_out
    in

    (* Apply the return sanitizer. *)
    let sanitize_return sanitize (source_taint, taint_in_taint_out, sink_taint) =
      let root = AccessPath.Root.LocalResult in
      let source_taint, taint_in_taint_out =
        (* def foo() -> Sanitize[TaintSource[...]] *)
        match sanitize.Sanitize.sources with
        | Some Sanitize.AllSources ->
            let source_taint = ForwardState.remove root source_taint in
            source_taint, taint_in_taint_out
        | Some (Sanitize.SpecificSources sanitized_sources) ->
            let filter_sources = function
              | None -> ForwardState.Tree.bottom
              | Some taint_tree -> ForwardState.Tree.sanitize sanitized_sources taint_tree
            in
            let source_taint = ForwardState.update source_taint root ~f:filter_sources in
            let taint_in_taint_out = sanitize_tito ~sources:sanitized_sources taint_in_taint_out in
            source_taint, taint_in_taint_out
        | None -> source_taint, taint_in_taint_out
      in
      let taint_in_taint_out =
        (* def foo() -> Sanitize[TaintInTaintOut[...]] *)
        match sanitize.Sanitize.tito with
        | Some AllTito -> BackwardState.remove root taint_in_taint_out
        | Some (SpecificTito { sanitized_tito_sources; sanitized_tito_sinks }) ->
            sanitize_tito
              ~sources:sanitized_tito_sources
              ~sinks:sanitized_tito_sinks
              taint_in_taint_out
        | _ -> taint_in_taint_out
      in
      let source_taint, taint_in_taint_out =
        (* def foo() -> Sanitize[TaintSink[...]] *)
        match sanitize.Sanitize.sinks with
        | Some Sanitize.AllSinks -> source_taint, taint_in_taint_out
        | Some (Sanitize.SpecificSinks sanitized_sinks) ->
            let sanitized_sinks_transforms = Sinks.Set.to_sanitize_transforms_exn sanitized_sinks in
            let source_taint =
              source_taint
              |> ForwardState.apply_sanitize_transforms sanitized_sinks_transforms
              |> ForwardState.transform ForwardTaint.kind Filter ~f:Flow.source_can_match_rule
            in
            let taint_in_taint_out = sanitize_tito ~sinks:sanitized_sinks taint_in_taint_out in
            source_taint, taint_in_taint_out
        | None -> source_taint, taint_in_taint_out
      in
      source_taint, taint_in_taint_out, sink_taint
    in

    (* Apply the parameter-specific sanitizers. *)
    let sanitize_parameter (parameter, sanitize) (source_taint, taint_in_taint_out, sink_taint) =
      let sink_taint, taint_in_taint_out =
        (* def foo(x: Sanitize[TaintSource[...]]): ... *)
        match sanitize.Sanitize.sources with
        | Some Sanitize.AllSources -> sink_taint, taint_in_taint_out
        | Some (Sanitize.SpecificSources sanitized_sources) ->
            let apply_taint_transforms = function
              | None -> BackwardState.Tree.bottom
              | Some taint_tree ->
                  let sanitized_sources_transforms =
                    Sources.Set.to_sanitize_transforms_exn sanitized_sources
                  in
                  taint_tree
                  |> BackwardState.Tree.apply_sanitize_transforms sanitized_sources_transforms
                  |> BackwardState.Tree.transform
                       BackwardTaint.kind
                       Filter
                       ~f:Flow.sink_can_match_rule
            in
            let sink_taint = BackwardState.update sink_taint parameter ~f:apply_taint_transforms in
            let taint_in_taint_out =
              sanitize_tito_parameter parameter ~sources:sanitized_sources taint_in_taint_out
            in
            sink_taint, taint_in_taint_out
        | None -> sink_taint, taint_in_taint_out
      in
      let taint_in_taint_out =
        (* def foo(x: Sanitize[TaintInTaintOut[...]]): ... *)
        match sanitize.Sanitize.tito with
        | Some AllTito -> BackwardState.remove parameter taint_in_taint_out
        | Some (SpecificTito { sanitized_tito_sources; sanitized_tito_sinks }) ->
            sanitize_tito_parameter
              parameter
              ~sources:sanitized_tito_sources
              ~sinks:sanitized_tito_sinks
              taint_in_taint_out
        | None -> taint_in_taint_out
      in
      let sink_taint, taint_in_taint_out =
        (* def foo(x: Sanitize[TaintSink[...]]): ... *)
        match sanitize.Sanitize.sinks with
        | Some Sanitize.AllSinks ->
            let sink_taint = BackwardState.remove parameter sink_taint in
            sink_taint, taint_in_taint_out
        | Some (Sanitize.SpecificSinks sanitized_sinks) ->
            let filter_sinks = function
              | None -> BackwardState.Tree.bottom
              | Some taint_tree -> BackwardState.Tree.sanitize sanitized_sinks taint_tree
            in
            let sink_taint = BackwardState.update sink_taint parameter ~f:filter_sinks in
            let taint_in_taint_out =
              sanitize_tito_parameter parameter ~sinks:sanitized_sinks taint_in_taint_out
            in
            sink_taint, taint_in_taint_out
        | None -> sink_taint, taint_in_taint_out
      in
      source_taint, taint_in_taint_out, sink_taint
    in

    let sanitize_root (root, sanitize) (source_taint, taint_in_taint_out, sink_taint) =
      match root with
      | AccessPath.Root.LocalResult ->
          sanitize_return sanitize (source_taint, taint_in_taint_out, sink_taint)
      | PositionalParameter _
      | NamedParameter _
      | StarParameter _
      | StarStarParameter _ ->
          sanitize_parameter (root, sanitize) (source_taint, taint_in_taint_out, sink_taint)
      | Variable _ -> failwith "unexpected"
    in
    let source_taint, taint_in_taint_out, sink_taint =
      SanitizeRootMap.fold
        SanitizeRootMap.KeyValue
        ~f:sanitize_root
        ~init:(source_taint, taint_in_taint_out, sink_taint)
        roots
    in
    { forward = { source_taint }; backward = { sink_taint; taint_in_taint_out }; sanitizers; modes }


  let analyze ~environment ~callable ~qualifier ~define ~sanitizers ~modes existing_model =
    let profiler =
      if Ast.Statement.Define.dump_perf (Ast.Node.value define) then
        TaintProfiler.create ()
      else
        TaintProfiler.none
    in
    let call_graph_of_define =
      Interprocedural.CallGraph.SharedMemory.get_or_compute
        ~callable
        ~environment
        ~define:(Ast.Node.value define)
    in
    let forward, result, triggered_sinks =
      TaintProfiler.track_duration ~profiler ~name:"Forward analysis" ~f:(fun () ->
          ForwardAnalysis.run
            ~profiler
            ~environment
            ~qualifier
            ~define
            ~call_graph_of_define
            ~existing_model)
    in
    let backward =
      TaintProfiler.track_duration ~profiler ~name:"Backward analysis" ~f:(fun () ->
          BackwardAnalysis.run
            ~profiler
            ~environment
            ~qualifier
            ~define
            ~call_graph_of_define
            ~existing_model
            ~triggered_sinks)
    in
    let forward, backward =
      if ModeSet.contains Mode.SkipAnalysis modes then
        empty_model.forward, empty_model.backward
      else
        forward, backward
    in
    let model = { forward; backward; sanitizers; modes } in
    let model =
      TaintProfiler.track_duration ~profiler ~name:"Sanitize" ~f:(fun () -> apply_sanitizers model)
    in
    TaintProfiler.dump profiler;
    result, model


  let analyze
      ~environment
      ~callable
      ~qualifier
      ~define:
        ({ Ast.Node.value = { Ast.Statement.Define.signature = { name; _ }; _ }; _ } as define)
      ~existing
    =
    let define_qualifier = Ast.Reference.delocalize name in
    let open Analysis in
    let open Ast in
    let module_reference =
      let global_resolution = TypeEnvironment.ReadOnly.global_resolution environment in
      let annotated_global_environment =
        GlobalResolution.annotated_global_environment global_resolution
      in
      (* Pysa inlines decorators when a function is decorated. However, we want issues and models to
         point to the lines in the module where the decorator was defined, not the module where it
         was inlined. So, look up the originating module, if any, and use that as the module
         qualifier. *)
      InlineDecorator.InlinedNameToOriginalName.get define_qualifier
      >>= AnnotatedGlobalEnvironment.ReadOnly.get_global_location annotated_global_environment
      >>| fun { Location.WithModule.path; _ } -> path
    in
    let qualifier = Option.value ~default:qualifier module_reference in
    match existing with
    | Some ({ modes; _ } as model) when ModeSet.contains Mode.SkipAnalysis modes ->
        let () = Log.info "Skipping taint analysis of %a" Target.pretty_print callable in
        [], model
    | Some ({ sanitizers; modes; _ } as model) ->
        analyze ~callable ~environment ~qualifier ~define ~sanitizers ~modes model
    | None ->
        analyze
          ~callable
          ~environment
          ~qualifier
          ~define
          ~sanitizers:Sanitizers.empty
          ~modes:ModeSet.empty
          empty_model


  let report = Taint.Reporting.report
end)
