with Web.Request;
with Web.Context;
with Web.Response;

--  Pre-handler guards: composable checks that run before a route handler.
--
--  A guard may enrich the request context (resolve a session, attach a
--  principal, stash a derived fact) and may short-circuit the request by
--  returning a response. This is the seam through which identity and
--  authorization gate a route without the framework core depending on either:
--  the framework runs the guards and never inspects what they decide.
package Web.Guard is

   type Guard_Decision is (Proceed, Halt);

   --  The result of running a guard: proceed to the next guard or the handler,
   --  or halt the request now and return Response instead.
   type Guard_Outcome (Decision : Guard_Decision := Proceed) is record
      case Decision is
         when Proceed =>
            null;
         when Halt =>
            Response : Web.Response.Response_Type;
      end case;
   end record;

   --  Continue to the next guard or the handler.
   function Proceed return Guard_Outcome;

   --  Stop now and return Response instead of invoking the handler.
   function Halt (Response : Web.Response.Response_Type) return Guard_Outcome;

   --  A guard runs before a handler with the request and the mutable context.
   --  It returns Proceed to continue or Halt (Response) to short-circuit.
   type Guard_Access is access function
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Guard_Outcome;

   --  A context-aware route handler: like Web.Server.Route_Handler, but it also
   --  receives the context the guards populated (so it can read the principal).
   type Contextual_Handler is access function
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type;

end Web.Guard;
