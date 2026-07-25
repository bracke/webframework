with Ada.Strings.Unbounded;
with Validation.Results;

--  Semantic validation for the "add project" form, using the standalone
--  Validation library. This is the `validate` step of the pipeline: the handler
--  decodes the form body into typed fields (Web.Binding-style), then validates
--  them here before touching the database. Validation is headless — it only
--  reports structured issues; the handler maps them to an HTTP 400.
package App.Project_Validation is

   use Ada.Strings.Unbounded;

   type Project_Input is record
      Name         : Unbounded_String;
      Status       : Unbounded_String;
      Project_Type : Unbounded_String;
      Functions    : Unbounded_String;
   end record;

   type Delete_Input is record
      Id : Integer := 0;
   end record;

   --  Validate the decoded fields against the project-form rules.
   function Validate (Input : Project_Input) return Validation.Results.Result;

   --  Validate a delete command: the id must be a positive project id.
   function Validate_Delete
     (Input : Delete_Input) return Validation.Results.Result;

   --  Render the result's issues as a JSON error body:
   --  {"status":"error","issues":[{"path":"$.name","message":"..."}, ...]}.
   function Error_JSON (Result : Validation.Results.Result) return String;

end App.Project_Validation;
