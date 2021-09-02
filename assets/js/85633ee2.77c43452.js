(self.webpackChunk=self.webpackChunk||[]).push([[585],{3905:(e,t,r)=>{"use strict";r.d(t,{Zo:()=>p,kt:()=>y});var n=r(7294);function o(e,t,r){return t in e?Object.defineProperty(e,t,{value:r,enumerable:!0,configurable:!0,writable:!0}):e[t]=r,e}function a(e,t){var r=Object.keys(e);if(Object.getOwnPropertySymbols){var n=Object.getOwnPropertySymbols(e);t&&(n=n.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),r.push.apply(r,n)}return r}function i(e){for(var t=1;t<arguments.length;t++){var r=null!=arguments[t]?arguments[t]:{};t%2?a(Object(r),!0).forEach((function(t){o(e,t,r[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(r)):a(Object(r)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(r,t))}))}return e}function s(e,t){if(null==e)return{};var r,n,o=function(e,t){if(null==e)return{};var r,n,o={},a=Object.keys(e);for(n=0;n<a.length;n++)r=a[n],t.indexOf(r)>=0||(o[r]=e[r]);return o}(e,t);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(e);for(n=0;n<a.length;n++)r=a[n],t.indexOf(r)>=0||Object.prototype.propertyIsEnumerable.call(e,r)&&(o[r]=e[r])}return o}var l=n.createContext({}),c=function(e){var t=n.useContext(l),r=t;return e&&(r="function"==typeof e?e(t):i(i({},t),e)),r},p=function(e){var t=c(e.components);return n.createElement(l.Provider,{value:t},e.children)},u={inlineCode:"code",wrapper:function(e){var t=e.children;return n.createElement(n.Fragment,{},t)}},d=n.forwardRef((function(e,t){var r=e.components,o=e.mdxType,a=e.originalType,l=e.parentName,p=s(e,["components","mdxType","originalType","parentName"]),d=c(r),y=o,m=d["".concat(l,".").concat(y)]||d[y]||u[y]||a;return r?n.createElement(m,i(i({ref:t},p),{},{components:r})):n.createElement(m,i({ref:t},p))}));function y(e,t){var r=arguments,o=t&&t.mdxType;if("string"==typeof e||o){var a=r.length,i=new Array(a);i[0]=d;var s={};for(var l in t)hasOwnProperty.call(t,l)&&(s[l]=t[l]);s.originalType=e,s.mdxType="string"==typeof e?e:o,i[1]=s;for(var c=2;c<a;c++)i[c]=r[c];return n.createElement.apply(null,i)}return n.createElement.apply(null,r)}d.displayName="MDXCreateElement"},1716:(e,t,r)=>{"use strict";r.r(t),r.d(t,{frontMatter:()=>l,metadata:()=>c,toc:()=>p,default:()=>y});var n,o=r(2122),a=r(9756),i=(r(7294),r(3905)),s=["components"],l={id:"pysa-additional-resources",title:"Additional Resources",sidebar_label:"Additional Resources"},c={unversionedId:"pysa-additional-resources",id:"pysa-additional-resources",isDocsHomePage:!1,title:"Additional Resources",description:"Public Talks",source:"@site/docs/pysa_resources.md",sourceDirName:".",slug:"/pysa-additional-resources",permalink:"/docs/pysa-additional-resources",editUrl:"https://github.com/facebook/pyre-check/tree/main/documentation/website/docs/pysa_resources.md",version:"current",sidebar_label:"Additional Resources",frontMatter:{id:"pysa-additional-resources",title:"Additional Resources",sidebar_label:"Additional Resources"},sidebar:"pysa",previous:{title:"6065 - Commandline arguments injection",permalink:"/docs/warning_codes/code-6065-public"},next:{title:"Exploring Taint Models Interactively",permalink:"/docs/pysa-explore"}},p=[{value:"Public Talks",id:"public-talks",children:[]}],u=(n="Internal",function(e){return console.warn("Component "+n+" was not imported, exported, or provided by MDXProvider as global scope"),(0,i.kt)("div",e)}),d={toc:p};function y(e){var t=e.components,r=(0,a.Z)(e,s);return(0,i.kt)("wrapper",(0,o.Z)({},d,r,{components:t,mdxType:"MDXLayout"}),(0,i.kt)("h2",{id:"public-talks"},"Public Talks"),(0,i.kt)("p",null,"Pysa has been discussed at a number of conferences. These talks provide\nadditional details and motivation for the project:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("a",{parentName:"li",href:"https://www.youtube.com/watch?v=hWV8t494N88"},"PyCon 2018")," - Open sourceing of\nPyre and the deeper static analysis (Pysa) that it enables"),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("a",{parentName:"li",href:"https://www.youtube.com/watch?v=ZplZ8ZBwu0Q"},"PyCon 2019")," & ",(0,i.kt)("a",{parentName:"li",href:"https://www.facebook.com/atscaleevents/videos/494471881397184"},"Security\n@Scale")," -\nBasics of how Pysa works"),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("a",{parentName:"li",href:"https://developers.facebook.com/videos/2019/facebook-loves-python-and-python-loves-facebook/"},"F8 (at\n16:00)")," -\nHow Pyre works on Instagram"),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("a",{parentName:"li",href:"https://www.youtube.com/watch?v=8I3zlvtpOww"},"DEF CON 28")," - Tutorial on how to\nget started with Pysa")),(0,i.kt)("p",null,"We've also shared a ",(0,i.kt)("a",{parentName:"p",href:"https://engineering.fb.com/security/pysa/"},"blog post on our engineering\nblog")," which covers how we developed\nPysa, how we use it, how it works, and it's results."),(0,i.kt)(u,{mdxType:"Internal"}))}y.isMDXComponent=!0}}]);