with GNAT.Sockets;
with Ada.Streams;
with System;

package Web.Connection is
   type Connection_Type is limited private;
   type Connection_Access is access all Connection_Type;

   --  Initialize a plain TCP connection wrapper.
   --  @param Item Connection wrapper.
   --  @param Socket Connected TCP socket, not No_Socket.
   --  @return No return value.
   procedure Open_Plain
     (Item   : in out Connection_Type;
      Socket : GNAT.Sockets.Socket_Type);

   --  Initialize a TLS connection wrapper.
   --  @param Item Connection wrapper.
   --  @param Socket Connected TCP socket, not No_Socket.
   --  @param TLS_Handle Opaque TLS connection handle, not null.
   --  @return No return value.
   procedure Open_TLS
     (Item       : in out Connection_Type;
      Socket     : GNAT.Sockets.Socket_Type;
      TLS_Handle : System.Address);

   --  Return the underlying TCP socket.
   --  @param Item Connection wrapper.
   --  @return Underlying socket.
   function Socket (Item : Connection_Type) return GNAT.Sockets.Socket_Type;

   --  Report whether this connection is TLS-protected.
   --  @param Item Connection wrapper.
   --  @return True for TLS connections.
   function Is_TLS (Item : Connection_Type) return Boolean;

   --  Receive bytes from the connection.
   --  @param Item Connection wrapper.
   --  @param Buffer Destination buffer.
   --  @param Last Last received element, or before Buffer'First on close.
   --  @return No return value.
   procedure Receive
     (Item   : in out Connection_Type;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   --  Send bytes on the connection.
   --  @param Item Connection wrapper.
   --  @param Buffer Source buffer.
   --  @param Last Last sent element, or before Buffer'First on close.
   --  @return No return value.
   procedure Send
     (Item   : in out Connection_Type;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   --  Send all text bytes on the connection.
   --  @param Item Connection wrapper.
   --  @param Data Text bytes to send.
   --  @return No return value.
   procedure Send_All
     (Item : in out Connection_Type;
      Data : String);

   --  Close the connection and its underlying socket.
   --  @param Item Connection wrapper.
   --  @return No return value.
   procedure Close (Item : in out Connection_Type);

private
   type Connection_Type is limited record
      Raw_Socket : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      TLS_Handle : System.Address := System.Null_Address;
   end record;
end Web.Connection;
