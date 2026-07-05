with GNAT.Sockets;
with Ada.Strings.Unbounded;
with Web.Connection;
with Web.Request;

package Web.WebSocket is
   type Opcode is (Text_Frame, Close_Frame, Ping_Frame, Pong_Frame);

   type Frame is record
      Frame_Type : Opcode := Text_Frame;
      Payload    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Validate whether a request is a WebSocket upgrade.
   --  @param Request HTTP request.
   --  @return True when required upgrade headers are present.
   function Is_Upgrade (Request : Web.Request.Request_Type) return Boolean;

   --  Compute Sec-WebSocket-Accept.
   --  @param Key Sec-WebSocket-Key header.
   --  @return Accept key.
   function Accept_Key (Key : String) return String;

   --  Encode an unmasked server text frame.
   --  @param Text Payload text.
   --  @return Frame bytes.
   function Encode_Text (Text : String) return String;

   --  Encode an unmasked close frame.
   --  @return Frame bytes.
   function Encode_Close return String;

   --  Decode one complete client frame from bytes.
   --  @param Data Frame bytes.
   --  @param Max_Size Maximum allowed payload size.
   --  @return Decoded frame.
   function Decode_Frame (Data : String; Max_Size : Natural) return Frame;

   --  Receive and decode one complete client frame from a socket.
   --  @param Socket Connected socket.
   --  @param Max_Size Maximum allowed payload size.
   --  @return Decoded frame.
   function Receive_Frame
     (Socket   : GNAT.Sockets.Socket_Type;
      Max_Size : Natural) return Frame;

   --  Receive and decode one complete client frame from a connection.
   --  @param Conn Connected transport.
   --  @param Max_Size Maximum allowed payload size.
   --  @return Decoded frame.
   function Receive_Frame
     (Conn     : in out Web.Connection.Connection_Type;
      Max_Size : Natural) return Frame;

   --  Return a decoded frame payload.
   --  @param Item Decoded frame.
   --  @return Payload text.
   function Payload (Item : Frame) return String;

   --  Send text on a WebSocket.
   --  @param Socket Connected socket.
   --  @param Text Payload text.
   --  @return No return value.
   procedure Send_Text (Socket : GNAT.Sockets.Socket_Type; Text : String);

   --  Send text on a WebSocket connection.
   --  @param Conn Connected transport.
   --  @param Text Payload text.
   --  @return No return value.
   procedure Send_Text
     (Conn : in out Web.Connection.Connection_Type;
      Text : String);

   --  Send a close frame on a WebSocket.
   --  @param Socket Connected socket.
   --  @return No return value.
   procedure Send_Close (Socket : GNAT.Sockets.Socket_Type);

   --  Send a close frame on a WebSocket connection.
   --  @param Conn Connected transport.
   --  @return No return value.
   procedure Send_Close (Conn : in out Web.Connection.Connection_Type);

   --  Send a pong frame on a WebSocket.
   --  @param Socket Connected socket.
   --  @param Text Pong payload.
   --  @return No return value.
   procedure Send_Pong (Socket : GNAT.Sockets.Socket_Type; Text : String);

   --  Send a pong frame on a WebSocket connection.
   --  @param Conn Connected transport.
   --  @param Text Pong payload.
   --  @return No return value.
   procedure Send_Pong
     (Conn : in out Web.Connection.Connection_Type;
      Text : String);
end Web.WebSocket;
