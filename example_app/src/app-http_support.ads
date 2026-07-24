--  Support for the HTTP-level integration test. The route handler and the
--  state callback live here (a library-level package) so their 'Access can be
--  registered with the framework's library-level access types; a main
--  procedure's nested subprograms cannot.
package App.Http_Support is

   --  Run the HTTP-level integration checks and report the failure count.
   --  @param Failures Number of checks that failed.
   --  @return No return value.
   procedure Run (Failures : out Natural);

end App.Http_Support;
