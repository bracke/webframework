with Web.Binding.Errors;
with Web.Binding.Results;
with Web.Binding.Diagnostics;

--  Typed-handler dispatch and failure classification.
--
--  The typed-handler adapter runs a declared binder's result: on success it
--  invokes the application with the fully typed value (the handler only ever
--  sees complete input); on failure it hands a response mapper a Failure_Class
--  and the errors. Binding never builds a response itself -- it classifies, the
--  application maps. Classification is by error id: malformed / missing input is
--  Bad_Request (400), an unsupported or missing media type is
--  Unsupported_Media_Type (415), an over-size body/field is Payload_Too_Large
--  (413), a binding-configuration fault is Internal_Error (500); a route
--  parameter failure may be Not_Found (404) by route policy.
package Web.Binding.Requests is

   type Failure_Class is
     (Bad_Request,
      Unsupported_Media_Type,
      Payload_Too_Large,
      Not_Found,
      Internal_Error);

   --  Classify a single error id.
   --  @param Id The error id.
   --  @return The failure class.
   function Classify (Id : Web.Binding.Errors.Error_Id) return Failure_Class;

   --  Classify an error collection, taking the most severe class. When
   --  Route_Not_Found and the result would be Bad_Request but a route-parameter
   --  error is present, the class becomes Not_Found (route policy).
   --  @param Errors The errors.
   --  @param Route_Not_Found Whether a route failure maps to 404.
   --  @return The failure class.
   function Classify
     (Errors          : Web.Binding.Errors.Error_Collection;
      Route_Not_Found : Boolean := False) return Failure_Class;

   --  Run a typed handler over a bind result. On_Success is invoked with the
   --  typed value only when the bind succeeded; otherwise On_Failure receives
   --  the classification and the errors. The application supplies both.
   generic
      type Input is private;
      with package Input_Results is new Web.Binding.Results (Input);
      with procedure On_Success (Value : Input);
      with procedure On_Failure
        (Class  : Failure_Class;
         Errors : Web.Binding.Errors.Error_Collection);
   procedure Dispatch
     (Result          : Input_Results.Result;
      Route_Not_Found : Boolean := False;
      Sink            : access Web.Binding.Diagnostics.Sink'Class := null;
      Correlation     : String := "";
      Route           : String := "");

end Web.Binding.Requests;
