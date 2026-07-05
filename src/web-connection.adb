with Web.Errors;
with Web.TLS;

package body Web.Connection is
   use type Ada.Streams.Stream_Element_Offset;
   use type GNAT.Sockets.Socket_Type;
   use type System.Address;

   procedure Open_Plain
     (Item   : in out Connection_Type;
      Socket : GNAT.Sockets.Socket_Type) is
   begin
      Item.Raw_Socket := Socket;
      Item.TLS_Handle := System.Null_Address;
   end Open_Plain;

   procedure Open_TLS
     (Item       : in out Connection_Type;
      Socket     : GNAT.Sockets.Socket_Type;
      TLS_Handle : System.Address) is
   begin
      Item.Raw_Socket := Socket;
      Item.TLS_Handle := TLS_Handle;
   end Open_TLS;

   function Socket (Item : Connection_Type) return GNAT.Sockets.Socket_Type is
   begin
      return Item.Raw_Socket;
   end Socket;

   function Is_TLS (Item : Connection_Type) return Boolean is
   begin
      return Item.TLS_Handle /= System.Null_Address;
   end Is_TLS;

   procedure Receive
     (Item   : in out Connection_Type;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset) is
   begin
      if Is_TLS (Item) then
         Web.TLS.Read (Item.TLS_Handle, Buffer, Last);
      else
         GNAT.Sockets.Receive_Socket (Item.Raw_Socket, Buffer, Last);
      end if;
   end Receive;

   procedure Send
     (Item   : in out Connection_Type;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset) is
   begin
      if Is_TLS (Item) then
         Web.TLS.Write (Item.TLS_Handle, Buffer, Last);
      else
         GNAT.Sockets.Send_Socket (Item.Raw_Socket, Buffer, Last);
      end if;
   end Send;

   procedure Send_All
     (Item : in out Connection_Type;
      Data : String)
   is
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. Data'Length);
      First     : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Last_Sent : Ada.Streams.Stream_Element_Offset;
   begin
      for Index_Value in Data'Range loop
         Buffer (Ada.Streams.Stream_Element_Offset (Index_Value - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Data (Index_Value)));
      end loop;

      while First <= Buffer'Last loop
         Send (Item, Buffer (First .. Buffer'Last), Last_Sent);
         if Last_Sent < First then
            raise Web.Errors.Protocol_Error with "connection send failed";
         end if;
         First := Last_Sent + 1;
      end loop;
   end Send_All;

   procedure Close (Item : in out Connection_Type) is
   begin
      if Item.TLS_Handle /= System.Null_Address then
         Web.TLS.Close (Item.TLS_Handle);
      end if;

      if Item.Raw_Socket /= GNAT.Sockets.No_Socket then
         GNAT.Sockets.Close_Socket (Item.Raw_Socket);
         Item.Raw_Socket := GNAT.Sockets.No_Socket;
      end if;
   exception
      when others =>
         Item.Raw_Socket := GNAT.Sockets.No_Socket;
         Item.TLS_Handle := System.Null_Address;
   end Close;
end Web.Connection;
