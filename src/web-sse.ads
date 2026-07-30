--  Web.SSE — Server-Sent Events (the text/event-stream format). Where a
--  WebSocket is a bidirectional channel, SSE is a one-way stream the server
--  pushes to the client over a long-lived HTTP response: progress, logs, live
--  updates. Register a stream route with Web.Server.Server_Sent_Events; the
--  server writes Response_Headers, then hands the connection to a handler that
--  calls Send_Event over time and returns when the stream ends.
--
--  The Format_* functions are pure (they build the wire text) and are the
--  security-critical part: multi-line data is split into one "data:" line each,
--  and CR/LF are stripped from the event name and id, so no caller-supplied
--  value can forge a field or terminate the event early. The Send_* procedures
--  wrap them, reporting Ok = False when the connection is closed or broken.
with Web.Connection;
package Web.SSE is

   --  The HTTP response head that opens an event stream (status line, the
   --  event-stream headers, and the blank line). The server writes this once,
   --  before invoking the handler.
   function Response_Headers return String;

   --  The wire text of one event: an optional "event:" line, an optional "id:"
   --  line, one "data:" line per line of Data, then a terminating blank line.
   function Format_Event
     (Data  : String;
      Event : String := "";
      Id    : String := "") return String;

   --  The wire text of a comment line (": text"), commonly a keep-alive.
   function Format_Comment (Text : String) return String;

   --  The wire text of a reconnection-delay hint ("retry: <ms>").
   function Format_Retry (Milliseconds : Natural) return String;

   --  Send one event. Ok is False on a closed/broken connection.
   procedure Send_Event
     (Conn  : in out Web.Connection.Connection_Type;
      Data  : String;
      Event : String := "";
      Id    : String := "";
      Ok    : out Boolean);

   --  Send a comment / heartbeat. Ok is False on a closed/broken connection.
   procedure Send_Comment
     (Conn : in out Web.Connection.Connection_Type;
      Text : String;
      Ok   : out Boolean);

   --  Send a reconnection-delay hint. Ok is False on a closed/broken connection.
   procedure Send_Retry
     (Conn         : in out Web.Connection.Connection_Type;
      Milliseconds : Natural;
      Ok           : out Boolean);

end Web.SSE;
