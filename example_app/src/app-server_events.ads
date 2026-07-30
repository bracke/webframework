--  App.Server_Events — a small Server-Sent Events demo for the showcase app.
--  Clock_Stream pushes a short burst of "tick" events (then an "end" event) over
--  a live text/event-stream; Demo_Page serves an HTML page whose EventSource
--  client lists them as they arrive.
with Web.Connection;
with Web.Request;
with Web.Response;
with Web.Context;
package App.Server_Events is

   --  The SSE handler for /events: emits six "tick" events half a second apart,
   --  then a final "end" event, then returns (which closes the stream). It stops
   --  early if the client disconnects.
   procedure Clock_Stream
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);

   --  The /events-demo page: subscribes to /events with EventSource. A guarded
   --  (context-aware) route handler.
   function Demo_Page
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type;

end App.Server_Events;
