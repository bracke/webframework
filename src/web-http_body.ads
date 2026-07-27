with Ada.Streams;
with Web.Connection;

--  A bounded, streaming reader for a request body. It delivers the body in
--  fixed-size chunks without ever holding the whole body in memory: first any
--  bytes already read while parsing the headers (the "leftover"), then the
--  remainder pulled from the connection, up to the declared Content-Length.
--
--  It backs the server's streaming upload lane, so a large upload is consumed
--  chunk by chunk (into a webuploads session, via an adapter) rather than
--  buffered. In memory mode (Conn = null) the whole body is supplied as the
--  leftover, which makes the streaming consumers unit-testable without a socket.
package Web.Http_Body is

   type Connection_Ref is access all Web.Connection.Connection_Type;

   --  Largest header+leftover block the server will hold; a request head (and
   --  the body bytes that arrive in the same reads) beyond this is rejected.
   Max_Leftover : constant := 65_536;

   type Reader is limited private;

   --  Configure a reader. Leftover is the body bytes already read past the
   --  header terminator; Content_Length is the whole declared body length
   --  (Leftover'Length of it is already in hand). Conn may be null (memory mode:
   --  Leftover must then contain the entire body).
   procedure Start
     (Self           : in out Reader;
      Conn           : Connection_Ref;
      Leftover       : Ada.Streams.Stream_Element_Array;
      Content_Length : Natural)
     with Pre => Leftover'Length <= Max_Leftover;

   --  Deliver the next chunk into Buffer. Last is the last filled index (below
   --  Buffer'First when nothing was delivered this call). Done is True once the
   --  whole Content-Length has been delivered. Closed is True if the connection
   --  ended before the declared length was received (a truncated body).
   procedure Read
     (Self   : in out Reader;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Done   : out Boolean;
      Closed : out Boolean);

   --  Content bytes not yet delivered.
   function Remaining (Self : Reader) return Natural;

private

   type Reader is limited record
      Conn      : Connection_Ref := null;
      Leftover  : Ada.Streams.Stream_Element_Array (1 .. Max_Leftover);
      Left_Len  : Natural := 0;   --  valid leftover bytes
      Left_Pos  : Natural := 0;   --  leftover bytes already delivered
      To_Read   : Natural := 0;   --  content bytes still to pull from the socket
   end record;

end Web.Http_Body;
