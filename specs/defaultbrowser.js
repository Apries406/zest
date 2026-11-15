var __zestModule=(()=>{var o=Object.defineProperty;var a=Object.getOwnPropertyDescriptor;var i=Object.getOwnPropertyNames;var c=Object.prototype.hasOwnProperty;var p=(e,r)=>{for(var t in r)o(e,t,{get:r[t],enumerable:!0})},u=(e,r,t,n)=>{if(r&&typeof r=="object"||typeof r=="function")for(let s of i(r))!c.call(e,s)&&s!==t&&o(e,s,{get:()=>r[s],enumerable:!(n=a(r,s))||n.enumerable});return e};var l=e=>u(o({},"__esModule",{value:!0}),e);var g={};p(g,{default:()=>d});var m={script:["defaultbrowser"],postProcess:function(e){return e.split(`
`).map(r=>r.startsWith("*")?{}:{name:r.trim()})}},f={name:"defaultbrowser",description:"Change your default browser from the CLI",args:{isOptional:!0,generators:m}},d=f;return l(g);})();

var __zestSpec = __zestModule.default;
