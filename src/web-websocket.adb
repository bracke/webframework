with Ada.Streams;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with CryptoLib.Hashes;
with Interfaces;
with Web.Connection;
with Web.Errors;

package body Web.WebSocket is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_8;

   Magic : constant String := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
   Base64_Table : constant String := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   function Is_Base64_Character (Ch : Character) return Boolean is
   begin
      return (Ch in 'A' .. 'Z')
        or else (Ch in 'a' .. 'z')
        or else (Ch in '0' .. '9')
        or else Ch = '+'
        or else Ch = '/';
   end Is_Base64_Character;

   function Is_Valid_Client_Key (Key : String) return Boolean is
      Padding_Start : Natural := 0;
   begin
      if Key'Length /= 24 then
         return False;
      end if;

      for Index_Value in Key'Range loop
         if Key (Index_Value) = '=' then
            if Padding_Start = 0 then
               Padding_Start := Index_Value;
            end if;
         elsif Padding_Start /= 0 or else not Is_Base64_Character (Key (Index_Value)) then
            return False;
         end if;
      end loop;

      return Padding_Start = Key'Last - 1;
   end Is_Valid_Client_Key;

   function Has_Token (Value : String; Token : String) return Boolean is
      Lower_Value : constant String := Ada.Characters.Handling.To_Lower (Value);
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Lower_Value'First;
      Comma_Pos   : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      loop
         Comma_Pos := Ada.Strings.Fixed.Index (Lower_Value (Start_Pos .. Lower_Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Lower_Value'Last else Comma_Pos - 1);
            Item     : constant String :=
              Ada.Strings.Fixed.Trim (Lower_Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
         begin
            if Item = Lower_Token then
               return True;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return False;
   end Has_Token;

   function To_Bytes (Data : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for Index_Value in Data'Range loop
         Result (Ada.Streams.Stream_Element_Offset (Index_Value - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Data (Index_Value)));
      end loop;
      return Result;
   end To_Bytes;

   function To_Stream_Array
     (Digest : CryptoLib.Hashes.SHA1_Digest) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Digest'Length));
   begin
      for Index_Value in Digest'Range loop
         Result (Ada.Streams.Stream_Element_Offset (Index_Value)) := Digest (Index_Value);
      end loop;
      return Result;
   end To_Stream_Array;

   function Is_Upgrade (Request : Web.Request.Request_Type) return Boolean is
   begin
      return Web.Request.Method (Request) = "GET"
        and then Web.Request.Has_Header (Request, "Upgrade")
        and then Web.Request.Has_Header (Request, "Connection")
        and then Web.Request.Has_Header (Request, "Sec-WebSocket-Key")
        and then Web.Request.Has_Header (Request, "Sec-WebSocket-Version")
        and then Has_Token (Web.Request.Header (Request, "Upgrade"), "websocket")
        and then Has_Token (Web.Request.Header (Request, "Connection"), "upgrade")
        and then Web.Request.Header (Request, "Sec-WebSocket-Version") = "13"
        and then Is_Valid_Client_Key (Web.Request.Header (Request, "Sec-WebSocket-Key"));
   end Is_Upgrade;

   function Base64 (Bytes : Ada.Streams.Stream_Element_Array) return String is
      Result : Unbounded_String;
      Index_Value : Ada.Streams.Stream_Element_Offset := Bytes'First;
      B1 : Natural;
      B2 : Natural;
      B3 : Natural;
      N  : Natural;
   begin
      while Index_Value <= Bytes'Last loop
         B1 := Natural (Bytes (Index_Value));
         if Index_Value + 1 <= Bytes'Last then
            B2 := Natural (Bytes (Index_Value + 1));
         else
            B2 := 0;
         end if;
         if Index_Value + 2 <= Bytes'Last then
            B3 := Natural (Bytes (Index_Value + 2));
         else
            B3 := 0;
         end if;

         N := B1 * 65_536 + B2 * 256 + B3;
         Append (Result, Base64_Table ((N / 262_144) mod 64 + 1));
         Append (Result, Base64_Table ((N / 4_096) mod 64 + 1));
         if Index_Value + 1 <= Bytes'Last then
            Append (Result, Base64_Table ((N / 64) mod 64 + 1));
         else
            Append (Result, "=");
         end if;
         if Index_Value + 2 <= Bytes'Last then
            Append (Result, Base64_Table (N mod 64 + 1));
         else
            Append (Result, "=");
         end if;
         Index_Value := Index_Value + 3;
      end loop;
      return To_String (Result);
   end Base64;

   function Accept_Key (Key : String) return String is
   begin
      return Base64 (To_Stream_Array (CryptoLib.Hashes.SHA1 (To_Bytes (Key & Magic))));
   end Accept_Key;

   function Encode_Frame (Op : Natural; Text : String) return String is
      Result : Unbounded_String;
      Length : constant Natural := Text'Length;
   begin
      Append (Result, Character'Val (16#80# + Op));
      if Length <= 125 then
         Append (Result, Character'Val (Length));
      elsif Length <= 65_535 then
         Append (Result, Character'Val (126));
         Append (Result, Character'Val (Length / 256));
         Append (Result, Character'Val (Length mod 256));
      else
         raise Web.Errors.Protocol_Error with "oversized websocket frame";
      end if;
      Append (Result, Text);
      return To_String (Result);
   end Encode_Frame;

   function Encode_Text (Text : String) return String is
   begin
      return Encode_Frame (1, Text);
   end Encode_Text;

   function Encode_Close return String is
   begin
      return Encode_Frame (8, "");
   end Encode_Close;

   function Encode_Pong (Text : String) return String is
   begin
      return Encode_Frame (10, Text);
   end Encode_Pong;

   function Is_Valid_Close_Code (Code : Natural) return Boolean is
   begin
      if Code in 1_000 .. 1_014 then
         return Code not in 1_004 .. 1_006 and then Code /= 1_015;
      end if;

      return Code in 3_000 .. 4_999;
   end Is_Valid_Close_Code;

   function Decode_Frame (Data : String; Max_Size : Natural) return Frame is
      First_Byte : Natural;
      Second_Byte : Natural;
      Payload_Length : Natural;
      Masked : Boolean;
      Cursor : Natural := Data'First;
      Mask : String (1 .. 4);
      Payload : Unbounded_String;
      Op : Natural;
   begin
      if Data'Length < 2 then
         raise Web.Errors.Protocol_Error with "short websocket frame";
      end if;

      First_Byte := Character'Pos (Data (Cursor));
      Cursor := Cursor + 1;
      Second_Byte := Character'Pos (Data (Cursor));
      Cursor := Cursor + 1;

      if First_Byte mod 16#80# >= 16#10# then
         raise Web.Errors.Protocol_Error with "websocket extensions are not supported";
      end if;

      if First_Byte < 16#80# then
         raise Web.Errors.Protocol_Error with "fragmented websocket frame";
      end if;

      Op := First_Byte mod 16;
      Masked := Second_Byte >= 16#80#;
      Payload_Length := Second_Byte mod 16#80#;

      if Payload_Length = 126 then
         if Data'Length < Cursor - Data'First + 2 then
            raise Web.Errors.Protocol_Error with "short websocket frame";
         end if;
         if Op in 8 .. 10 then
            raise Web.Errors.Protocol_Error with "oversized websocket control frame";
         end if;
         Payload_Length := Character'Pos (Data (Cursor)) * 256 + Character'Pos (Data (Cursor + 1));
         if Payload_Length <= 125 then
            raise Web.Errors.Protocol_Error with "non-minimal websocket length";
         end if;
         Cursor := Cursor + 2;
      elsif Payload_Length = 127 then
         raise Web.Errors.Protocol_Error with "oversized websocket frame";
      end if;

      if Payload_Length > Max_Size then
         raise Web.Errors.Protocol_Error with "oversized websocket message";
      end if;

      if Op in 8 .. 10 and then Payload_Length > 125 then
         raise Web.Errors.Protocol_Error with "oversized websocket control frame";
      end if;

      if Op = 8 and then Payload_Length = 1 then
         raise Web.Errors.Protocol_Error with "invalid websocket close frame";
      end if;

      if not Masked then
         raise Web.Errors.Protocol_Error with "client frame is not masked";
      end if;

      if Data'Length < Cursor - Data'First + 4 + Payload_Length then
         raise Web.Errors.Protocol_Error with "short websocket frame";
      end if;

      for Offset in 1 .. 4 loop
         Mask (Offset) := Data (Cursor);
         Cursor := Cursor + 1;
      end loop;

      for Offset in 0 .. Payload_Length - 1 loop
         Append
           (Payload,
            Character'Val
              (Natural
                 (Interfaces.Unsigned_8 (Character'Pos (Data (Cursor + Offset)))
                  xor Interfaces.Unsigned_8 (Character'Pos (Mask (Offset mod 4 + 1))))));
      end loop;

      if Op = 8 and then Payload_Length >= 2 then
         declare
            Payload_Text : constant String := To_String (Payload);
            Code         : constant Natural :=
              Character'Pos (Payload_Text (Payload_Text'First)) * 256
              + Character'Pos (Payload_Text (Payload_Text'First + 1));
         begin
            if not Is_Valid_Close_Code (Code) then
               raise Web.Errors.Protocol_Error with "invalid websocket close code";
            end if;
         end;
      end if;

      case Op is
         when 1 =>
            return (Text_Frame, Payload);
         when 8 =>
            return (Close_Frame, Payload);
         when 9 =>
            return (Ping_Frame, Payload);
         when 10 =>
            return (Pong_Frame, Payload);
         when others =>
            raise Web.Errors.Protocol_Error with "unsupported websocket opcode";
      end case;
   end Decode_Frame;

   function Payload (Item : Frame) return String is
   begin
      return To_String (Item.Payload);
   end Payload;

   function Read_Exact
     (Socket : GNAT.Sockets.Socket_Type;
      Count  : Natural) return String
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset;
      Cursor : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Result : String (1 .. Count);
   begin
      while Cursor <= Buffer'Last loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer (Cursor .. Buffer'Last), Last);
         if Last < Cursor then
            raise Web.Errors.Protocol_Error with "websocket socket closed";
         end if;
         Cursor := Last + 1;
      end loop;

      for Index_Value in Result'Range loop
         Result (Index_Value) :=
           Character'Val
             (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index_Value - Result'First)));
      end loop;
      return Result;
   end Read_Exact;

   function Read_Exact
     (Conn  : in out Web.Connection.Connection_Type;
      Count : Natural) return String
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset;
      Cursor : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Result : String (1 .. Count);
   begin
      while Cursor <= Buffer'Last loop
         Web.Connection.Receive (Conn, Buffer (Cursor .. Buffer'Last), Last);
         if Last < Cursor then
            raise Web.Errors.Protocol_Error with "websocket socket closed";
         end if;
         Cursor := Last + 1;
      end loop;

      for Index_Value in Result'Range loop
         Result (Index_Value) :=
           Character'Val
             (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index_Value - Result'First)));
      end loop;
      return Result;
   end Read_Exact;

   function Receive_Frame
     (Socket   : GNAT.Sockets.Socket_Type;
      Max_Size : Natural) return Frame
   is
      Header         : constant String := Read_Exact (Socket, 2);
      Length_Code    : constant Natural := Character'Pos (Header (Header'First + 1)) mod 16#80#;
      Payload_Length : Natural := Length_Code;
      Extra          : Unbounded_String;
   begin
      if Length_Code = 126 then
         declare
            Bytes : constant String := Read_Exact (Socket, 2);
         begin
            Payload_Length :=
              Character'Pos (Bytes (Bytes'First)) * 256
              + Character'Pos (Bytes (Bytes'First + 1));
            Append (Extra, Bytes);
         end;
      elsif Length_Code = 127 then
         raise Web.Errors.Protocol_Error with "oversized websocket frame";
      end if;

      if Payload_Length > Max_Size then
         raise Web.Errors.Protocol_Error with "oversized websocket message";
      end if;

      declare
         Mask_And_Payload : constant String := Read_Exact (Socket, 4 + Payload_Length);
      begin
         return Decode_Frame (Header & To_String (Extra) & Mask_And_Payload, Max_Size);
      end;
   end Receive_Frame;

   function Receive_Frame
     (Conn     : in out Web.Connection.Connection_Type;
      Max_Size : Natural) return Frame
   is
      Header         : constant String := Read_Exact (Conn, 2);
      Length_Code    : constant Natural := Character'Pos (Header (Header'First + 1)) mod 16#80#;
      Payload_Length : Natural := Length_Code;
      Extra          : Unbounded_String;
   begin
      if Length_Code = 126 then
         declare
            Bytes : constant String := Read_Exact (Conn, 2);
         begin
            Payload_Length :=
              Character'Pos (Bytes (Bytes'First)) * 256
              + Character'Pos (Bytes (Bytes'First + 1));
            Append (Extra, Bytes);
         end;
      elsif Length_Code = 127 then
         raise Web.Errors.Protocol_Error with "oversized websocket frame";
      end if;

      if Payload_Length > Max_Size then
         raise Web.Errors.Protocol_Error with "oversized websocket message";
      end if;

      declare
         Mask_And_Payload : constant String := Read_Exact (Conn, 4 + Payload_Length);
      begin
         return Decode_Frame (Header & To_String (Extra) & Mask_And_Payload, Max_Size);
      end;
   end Receive_Frame;

   procedure Send_All (Socket : GNAT.Sockets.Socket_Type; Data : String) is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Data'Length);
      First  : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      for Index_Value in Data'Range loop
         Buffer (Ada.Streams.Stream_Element_Offset (Index_Value - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Data (Index_Value)));
      end loop;

      while First <= Buffer'Last loop
         GNAT.Sockets.Send_Socket (Socket, Buffer (First .. Buffer'Last), Last);
         if Last < First then
            raise Web.Errors.Protocol_Error with "websocket send failed";
         end if;
         First := Last + 1;
      end loop;
   end Send_All;

   procedure Send_All
     (Conn : in out Web.Connection.Connection_Type;
      Data : String) is
   begin
      Web.Connection.Send_All (Conn, Data);
   end Send_All;

   procedure Send_Text (Socket : GNAT.Sockets.Socket_Type; Text : String) is
   begin
      Send_All (Socket, Encode_Text (Text));
   end Send_Text;

   procedure Send_Text
     (Conn : in out Web.Connection.Connection_Type;
      Text : String) is
   begin
      Send_All (Conn, Encode_Text (Text));
   end Send_Text;

   procedure Send_Close (Socket : GNAT.Sockets.Socket_Type) is
   begin
      Send_All (Socket, Encode_Close);
   end Send_Close;

   procedure Send_Close (Conn : in out Web.Connection.Connection_Type) is
   begin
      Send_All (Conn, Encode_Close);
   end Send_Close;

   procedure Send_Pong (Socket : GNAT.Sockets.Socket_Type; Text : String) is
   begin
      Send_All (Socket, Encode_Pong (Text));
   end Send_Pong;

   procedure Send_Pong
     (Conn : in out Web.Connection.Connection_Type;
      Text : String) is
   begin
      Send_All (Conn, Encode_Pong (Text));
   end Send_Pong;
end Web.WebSocket;
