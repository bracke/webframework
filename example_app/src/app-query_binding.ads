with Web.Request;

--  Example use of the Web.Binding subsystem: bind the projects-listing query
--  parameters into a typed record. Demonstrates the source -> decoder ->
--  record-binder pipeline. The listing is read-only, so binding is fail-soft:
--  a malformed value falls back to the seeded default rather than erroring the
--  request (a form endpoint would surface the errors through Web.Binding.Forms
--  and a typed handler instead).
package App.Query_Binding is

   type Page_Number is range 1 .. 100_000;

   type Projects_Query is record
      Page       : Page_Number := 1;
      Alire_Only : Boolean := False;
   end record;

   --  Bind the "page" and "alire_only" query parameters from a request.
   --  @param Request The HTTP request.
   --  @return The typed query (defaults on absent or malformed input).
   function Bind (Request : Web.Request.Request_Type) return Projects_Query;

end App.Query_Binding;
