(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Core
open Analysis
open Interprocedural

include TypeInferenceResult.Register (struct
  let configuration : Configuration.Analysis.t option ref = ref None

  let init
      ~configuration:{ Configuration.StaticAnalysis.configuration = c; _ }
      ~scheduler:_
      ~environment:_
      ~functions:_
      ~stubs:_
    =
    configuration := Some c;
    { Result.initial_models = Callable.Map.empty; skip_overrides = Ast.Reference.Set.empty }


  let analyze ~callable:_ ~environment ~qualifier ~define ~existing:_ =
    let global_resolution = TypeEnvironment.ReadOnly.global_resolution environment in
    let ast_environment = GlobalResolution.ast_environment global_resolution in
    let maybe_source = AstEnvironment.ReadOnly.get_processed_source ast_environment qualifier in
    let result =
      match !configuration, maybe_source with
      | None, _ -> []
      | _, None -> []
      | Some configuration, Some source ->
          Inference.run_local ~configuration ~global_resolution ~source ~define
          |> List.map
               ~f:
                 (AnalysisError.instantiate
                    ~show_error_traces:configuration.show_error_traces
                    ~lookup:
                      (AstEnvironment.ReadOnly.get_real_path_relative
                         ~configuration
                         ast_environment))
    in
    result, TypeInferenceDomain.bottom
end)