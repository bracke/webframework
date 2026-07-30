--  App.Server_Events — the Server-Sent Events stream handler for the showcase
--  app. Clock_Stream pushes a short burst of "tick" events (then an "end" event)
--  over a live text/event-stream; the /events-demo *page* that consumes it lives
--  in App.Pages (rendered through the shared layout like every other page).
with Web.Connection;
with Web.Request;
package App.Server_Events is

   --  The SSE handler for /events: emits six "tick" events half a second apart,
   --  then a final "end" event, then returns (which closes the stream). It stops
   --  early if the client disconnects.
   procedure Clock_Stream
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);

end App.Server_Events;
