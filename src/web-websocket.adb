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
      Connection_Value : constant String := Web.Request.Header (Request, "Connection");
      Upgrade_Value : constant String := Web.Request.Header (Request, "Upgrade");
      Key_Value : constant String := Web.Request.Header (Request, "Sec-WebSocket-Key");
      Version_Value : constant String := Web.Request.Header (Request, "Sec-WebSocket-Version");
   begin
      return Web.Request.Method (Request) = "GET"
        and then Upgrade_Value'Length > 0
        and then Connection_Value'Length > 0
        and then Key_Value'Length > 0
        and then Version_Value'Length > 0
        and then Has_Token (Upgrade_Value, "websocket")
        and then Has_Token (Connection_Value, "upgrade")
        and then Version_Value = "13"
        and then Is_Valid_Client_Key (Key_Value);
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
      if not Is_Valid_Client_Key (Key) then
         raise Web.Errors.Protocol_Error with "invalid websocket key";
      end if;

      return Base64 (To_Stream_Array (CryptoLib.Hashes.SHA1 (To_Bytes (Key & Magic))));
   end Accept_Key;

   function Is_Valid_UTF8 (Value : String) return Boolean;

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
      if not Is_Valid_UTF8 (Text) then
         raise Web.Errors.Protocol_Error with "invalid websocket text utf8";
      end if;

      return Encode_Frame (1, Text);
   end Encode_Text;

   function Encode_Close return String is
   begin
      return Encode_Frame (8, "");
   end Encode_Close;

   function Encode_Pong (Text : String) return String is
   begin
      if Text'Length > 125 then
         raise Web.Errors.Protocol_Error with "oversized websocket control frame";
      end if;

      return Encode_Frame (10, Text);
   end Encode_Pong;

   function Is_Valid_Close_Code (Code : Natural) return Boolean is
   begin
      if Code in 1_000 .. 1_014 then
         return Code not in 1_004 .. 1_006 and then Code /= 1_015;
      end if;

      return Code in 3_000 .. 4_999;
   end Is_Valid_Close_Code;

   function Is_Valid_UTF8 (Value : String) return Boolean is
      Index_Value : Natural := Value'First;
      B1          : Natural;
      B2          : Natural;
      B3          : Natural;
      B4          : Natural;
   begin
      while Index_Value <= Value'Last loop
         B1 := Character'Pos (Value (Index_Value));

         if B1 <= 16#7F# then
            Index_Value := Index_Value + 1;
         elsif B1 in 16#C2# .. 16#DF# then
            if Index_Value + 1 > Value'Last then
               return False;
            end if;
            B2 := Character'Pos (Value (Index_Value + 1));
            if B2 not in 16#80# .. 16#BF# then
               return False;
            end if;
            Index_Value := Index_Value + 2;
         elsif B1 in 16#E0# .. 16#EF# then
            if Index_Value + 2 > Value'Last then
               return False;
            end if;
            B2 := Character'Pos (Value (Index_Value + 1));
            B3 := Character'Pos (Value (Index_Value + 2));
            if B3 not in 16#80# .. 16#BF#
              or else (B1 = 16#E0# and then B2 not in 16#A0# .. 16#BF#)
              or else (B1 = 16#ED# and then B2 not in 16#80# .. 16#9F#)
              or else (B1 /= 16#E0# and then B1 /= 16#ED# and then B2 not in 16#80# .. 16#BF#)
            then
               return False;
            end if;
            Index_Value := Index_Value + 3;
         elsif B1 in 16#F0# .. 16#F4# then
            if Index_Value + 3 > Value'Last then
               return False;
            end if;
            B2 := Character'Pos (Value (Index_Value + 1));
            B3 := Character'Pos (Value (Index_Value + 2));
            B4 := Character'Pos (Value (Index_Value + 3));
            if B3 not in 16#80# .. 16#BF#
              or else B4 not in 16#80# .. 16#BF#
              or else (B1 = 16#F0# and then B2 not in 16#90# .. 16#BF#)
              or else (B1 = 16#F4# and then B2 not in 16#80# .. 16#8F#)
              or else (B1 /= 16#F0# and then B1 /= 16#F4# and then B2 not in 16#80# .. 16#BF#)
            then
               return False;
            end if;
            Index_Value := Index_Value + 4;
         else
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_UTF8;

   function Decode_Frame (Data : String; Max_Size : Natural) return Frame is
      First_Byte : Natural;
      Second_Byte : Natural;
      Payload_Length : Natural;
      Masked : Boolean;
      Cursor : Natural := Data'First;
      Mask : String (1 .. 4);
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

      declare
         Payload_Text : String (1 .. Payload_Length);
         Text_Is_ASCII : Boolean := True;
         Close_Reason_Is_ASCII : Boolean := True;
      begin
         for Offset in 0 .. Payload_Length - 1 loop
            declare
               Data_Byte : constant Interfaces.Unsigned_8 :=
                 Interfaces.Unsigned_8 (Character'Pos (Data (Cursor + Offset)));
               Mask_Byte : constant Interfaces.Unsigned_8 :=
                 Interfaces.Unsigned_8 (Character'Pos (Mask (Offset mod 4 + 1)));
            begin
               Payload_Text (Payload_Text'First + Offset) :=
                 Character'Val (Natural (Data_Byte xor Mask_Byte));
               if Natural (Data_Byte xor Mask_Byte) > 16#7F# then
                  Text_Is_ASCII := False;
                  if Offset >= 2 then
                     Close_Reason_Is_ASCII := False;
                  end if;
               end if;
            end;
         end loop;

         if Op = 8 and then Payload_Length >= 2 then
            declare
               Code : constant Natural :=
                 Character'Pos (Payload_Text (Payload_Text'First)) * 256
                 + Character'Pos (Payload_Text (Payload_Text'First + 1));
            begin
               if not Is_Valid_Close_Code (Code) then
                  raise Web.Errors.Protocol_Error with "invalid websocket close code";
               end if;

               if Payload_Length > 2
                 and then not Close_Reason_Is_ASCII
                 and then not Is_Valid_UTF8 (Payload_Text (Payload_Text'First + 2 .. Payload_Text'Last))
               then
                  raise Web.Errors.Protocol_Error with "invalid websocket close reason";
               end if;
            end;
         end if;

         case Op is
            when 1 =>
               if not Text_Is_ASCII and then not Is_Valid_UTF8 (Payload_Text) then
                  raise Web.Errors.Protocol_Error with "invalid websocket text utf8";
               end if;
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Text_Frame,
                  Payload_Text   => Payload_Text);
            when 8 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Close_Frame,
                  Payload_Text   => Payload_Text);
            when 9 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Ping_Frame,
                  Payload_Text   => Payload_Text);
            when 10 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Pong_Frame,
                  Payload_Text   => Payload_Text);
            when others =>
               raise Web.Errors.Protocol_Error with "unsupported websocket opcode";
         end case;
      end;
   end Decode_Frame;

   function Payload (Item : Frame) return String is
   begin
      return Item.Payload_Text;
   end Payload;

   procedure With_Payload (Item : Frame) is
   begin
      Process (Item.Payload_Text);
   end With_Payload;

   procedure Receive_And_Process
     (Conn     : in out Web.Connection.Connection_Type;
      Max_Size : Natural)
   is
      Item : constant Frame := Receive_Frame (Conn, Max_Size);
   begin
      Process (Item.Frame_Type, Item.Payload_Text);
   end Receive_And_Process;

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

   function Read_Exact_Bytes
     (Socket : GNAT.Sockets.Socket_Type;
      Count  : Natural) return Ada.Streams.Stream_Element_Array
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset;
      Cursor : Ada.Streams.Stream_Element_Offset := Buffer'First;
   begin
      while Cursor <= Buffer'Last loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer (Cursor .. Buffer'Last), Last);
         if Last < Cursor then
            raise Web.Errors.Protocol_Error with "websocket socket closed";
         end if;
         Cursor := Last + 1;
      end loop;

      return Buffer;
   end Read_Exact_Bytes;

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

   function Read_Exact_Bytes
     (Conn  : in out Web.Connection.Connection_Type;
      Count : Natural) return Ada.Streams.Stream_Element_Array
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset;
      Cursor : Ada.Streams.Stream_Element_Offset := Buffer'First;
   begin
      while Cursor <= Buffer'Last loop
         Web.Connection.Receive (Conn, Buffer (Cursor .. Buffer'Last), Last);
         if Last < Cursor then
            raise Web.Errors.Protocol_Error with "websocket socket closed";
         end if;
         Cursor := Last + 1;
      end loop;

      return Buffer;
   end Read_Exact_Bytes;

   procedure Validate_Frame_Before_Payload
     (Header         : Ada.Streams.Stream_Element_Array;
      Payload_Length : Natural)
   is
      First_Byte : constant Natural := Natural (Header (Header'First));
      Op         : constant Natural := First_Byte mod 16;
   begin
      if First_Byte mod 16#80# >= 16#10# then
         raise Web.Errors.Protocol_Error with "websocket extensions are not supported";
      end if;

      if First_Byte < 16#80# then
         raise Web.Errors.Protocol_Error with "fragmented websocket frame";
      end if;

      if Op in 8 .. 10 and then Payload_Length > 125 then
         raise Web.Errors.Protocol_Error with "oversized websocket control frame";
      end if;

      if Op = 8 and then Payload_Length = 1 then
         raise Web.Errors.Protocol_Error with "invalid websocket close frame";
      end if;
   end Validate_Frame_Before_Payload;

   function Decode_Received_Frame
     (Header           : Ada.Streams.Stream_Element_Array;
      Payload_Length   : Natural;
      Mask_And_Payload : Ada.Streams.Stream_Element_Array) return Frame
   is
      use type Ada.Streams.Stream_Element_Offset;

      First_Byte : constant Natural := Natural (Header (Header'First));
      Second_Byte : constant Natural := Natural (Header (Header'First + 1));
      Masked     : constant Boolean := Second_Byte >= 16#80#;
      Op         : constant Natural := First_Byte mod 16;
      Payload_Start : constant Ada.Streams.Stream_Element_Offset := Mask_And_Payload'First + 4;
   begin
      if not Masked then
         raise Web.Errors.Protocol_Error with "client frame is not masked";
      end if;

      if Mask_And_Payload'Length /= Payload_Length + 4 then
         raise Web.Errors.Protocol_Error with "short websocket frame";
      end if;

      declare
         Payload_Text : String (1 .. Payload_Length);
         Text_Is_ASCII : Boolean := True;
         Close_Reason_Is_ASCII : Boolean := True;
         Mask_0 : constant Interfaces.Unsigned_8 :=
           Interfaces.Unsigned_8 (Mask_And_Payload (Mask_And_Payload'First));
         Mask_1 : constant Interfaces.Unsigned_8 :=
           Interfaces.Unsigned_8 (Mask_And_Payload (Mask_And_Payload'First + 1));
         Mask_2 : constant Interfaces.Unsigned_8 :=
           Interfaces.Unsigned_8 (Mask_And_Payload (Mask_And_Payload'First + 2));
         Mask_3 : constant Interfaces.Unsigned_8 :=
           Interfaces.Unsigned_8 (Mask_And_Payload (Mask_And_Payload'First + 3));
      begin
         for Offset in 0 .. Payload_Length - 1 loop
            declare
               Data_Byte : constant Interfaces.Unsigned_8 :=
                 Interfaces.Unsigned_8
                   (Mask_And_Payload
                      (Payload_Start + Ada.Streams.Stream_Element_Offset (Offset)));
               Mask_Byte : constant Interfaces.Unsigned_8 :=
                 (case Offset mod 4 is
                     when 0 => Mask_0,
                     when 1 => Mask_1,
                     when 2 => Mask_2,
                     when others => Mask_3);
            begin
               Payload_Text (Payload_Text'First + Offset) :=
                 Character'Val (Natural (Data_Byte xor Mask_Byte));
               if Natural (Data_Byte xor Mask_Byte) > 16#7F# then
                  Text_Is_ASCII := False;
                  if Offset >= 2 then
                     Close_Reason_Is_ASCII := False;
                  end if;
               end if;
            end;
         end loop;

         if Op = 8 and then Payload_Length >= 2 then
            declare
               Code : constant Natural :=
                 Character'Pos (Payload_Text (Payload_Text'First)) * 256
                 + Character'Pos (Payload_Text (Payload_Text'First + 1));
            begin
               if not Is_Valid_Close_Code (Code) then
                  raise Web.Errors.Protocol_Error with "invalid websocket close code";
               end if;

               if Payload_Length > 2
                 and then not Close_Reason_Is_ASCII
                 and then not Is_Valid_UTF8 (Payload_Text (Payload_Text'First + 2 .. Payload_Text'Last))
               then
                  raise Web.Errors.Protocol_Error with "invalid websocket close reason";
               end if;
            end;
         end if;

         case Op is
            when 1 =>
               if not Text_Is_ASCII and then not Is_Valid_UTF8 (Payload_Text) then
                  raise Web.Errors.Protocol_Error with "invalid websocket text utf8";
               end if;
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Text_Frame,
                  Payload_Text   => Payload_Text);
            when 8 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Close_Frame,
                  Payload_Text   => Payload_Text);
            when 9 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Ping_Frame,
                  Payload_Text   => Payload_Text);
            when 10 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Pong_Frame,
                  Payload_Text   => Payload_Text);
            when others =>
               raise Web.Errors.Protocol_Error with "unsupported websocket opcode";
         end case;
      end;
   end Decode_Received_Frame;

   function Decode_Received_Payload
     (Header         : Ada.Streams.Stream_Element_Array;
      Payload_Length : Natural;
      Mask           : Ada.Streams.Stream_Element_Array;
      Payload_Data   : Ada.Streams.Stream_Element_Array) return Frame
   is
      use type Ada.Streams.Stream_Element_Offset;

      First_Byte : constant Natural := Natural (Header (Header'First));
      Second_Byte : constant Natural := Natural (Header (Header'First + 1));
      Masked     : constant Boolean := Second_Byte >= 16#80#;
      Op         : constant Natural := First_Byte mod 16;
      Mask_0     : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Mask (Mask'First));
      Mask_1     : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Mask (Mask'First + 1));
      Mask_2     : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Mask (Mask'First + 2));
      Mask_3     : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Mask (Mask'First + 3));
   begin
      if not Masked then
         raise Web.Errors.Protocol_Error with "client frame is not masked";
      end if;

      if Mask'Length /= 4 or else Payload_Data'Length /= Payload_Length then
         raise Web.Errors.Protocol_Error with "short websocket frame";
      end if;

      declare
         Payload_Text : String (1 .. Payload_Length);
         Text_Is_ASCII : Boolean := True;
         Close_Reason_Is_ASCII : Boolean := True;
      begin
         for Offset in 0 .. Payload_Length - 1 loop
            declare
               Data_Byte : constant Interfaces.Unsigned_8 :=
                 Interfaces.Unsigned_8
                   (Payload_Data (Payload_Data'First + Ada.Streams.Stream_Element_Offset (Offset)));
               Mask_Byte : constant Interfaces.Unsigned_8 :=
                 (case Offset mod 4 is
                     when 0 => Mask_0,
                     when 1 => Mask_1,
                     when 2 => Mask_2,
                     when others => Mask_3);
               Decoded : constant Natural := Natural (Data_Byte xor Mask_Byte);
            begin
               Payload_Text (Payload_Text'First + Offset) := Character'Val (Decoded);
               if Decoded > 16#7F# then
                  Text_Is_ASCII := False;
                  if Offset >= 2 then
                     Close_Reason_Is_ASCII := False;
                  end if;
               end if;
            end;
         end loop;

         if Op = 8 and then Payload_Length >= 2 then
            declare
               Code : constant Natural :=
                 Character'Pos (Payload_Text (Payload_Text'First)) * 256
                 + Character'Pos (Payload_Text (Payload_Text'First + 1));
            begin
               if not Is_Valid_Close_Code (Code) then
                  raise Web.Errors.Protocol_Error with "invalid websocket close code";
               end if;

               if Payload_Length > 2
                 and then not Close_Reason_Is_ASCII
                 and then not Is_Valid_UTF8 (Payload_Text (Payload_Text'First + 2 .. Payload_Text'Last))
               then
                  raise Web.Errors.Protocol_Error with "invalid websocket close reason";
               end if;
            end;
         end if;

         case Op is
            when 1 =>
               if not Text_Is_ASCII and then not Is_Valid_UTF8 (Payload_Text) then
                  raise Web.Errors.Protocol_Error with "invalid websocket text utf8";
               end if;
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Text_Frame,
                  Payload_Text   => Payload_Text);
            when 8 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Close_Frame,
                  Payload_Text   => Payload_Text);
            when 9 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Ping_Frame,
                  Payload_Text   => Payload_Text);
            when 10 =>
               return
                 (Payload_Length => Payload_Length,
                  Frame_Type     => Pong_Frame,
                  Payload_Text   => Payload_Text);
            when others =>
               raise Web.Errors.Protocol_Error with "unsupported websocket opcode";
         end case;
      end;
   end Decode_Received_Payload;

   function Receive_Frame
     (Socket   : GNAT.Sockets.Socket_Type;
      Max_Size : Natural) return Frame
   is
      use type Ada.Streams.Stream_Element_Offset;

      Header         : constant Ada.Streams.Stream_Element_Array := Read_Exact_Bytes (Socket, 2);
      Length_Code    : constant Natural := Natural (Header (Header'First + 1)) mod 16#80#;
      Payload_Length : Natural := Length_Code;
   begin
      if Length_Code = 126 then
         declare
            Bytes : constant Ada.Streams.Stream_Element_Array := Read_Exact_Bytes (Socket, 2);
         begin
            Payload_Length :=
              Natural (Bytes (Bytes'First)) * 256
              + Natural (Bytes (Bytes'First + 1));
            if Payload_Length <= 125 then
               raise Web.Errors.Protocol_Error with "non-minimal websocket length";
            end if;
         end;
      elsif Length_Code = 127 then
         raise Web.Errors.Protocol_Error with "oversized websocket frame";
      end if;

      Validate_Frame_Before_Payload (Header, Payload_Length);

      if Payload_Length > Max_Size then
         raise Web.Errors.Protocol_Error with "oversized websocket message";
      end if;

      declare
         Mask : constant Ada.Streams.Stream_Element_Array := Read_Exact_Bytes (Socket, 4);
         Payload_Data : constant Ada.Streams.Stream_Element_Array :=
           Read_Exact_Bytes (Socket, Payload_Length);
      begin
         return Decode_Received_Payload (Header, Payload_Length, Mask, Payload_Data);
      end;
   end Receive_Frame;

   function Receive_Frame
     (Conn     : in out Web.Connection.Connection_Type;
      Max_Size : Natural) return Frame
   is
      use type Ada.Streams.Stream_Element_Offset;

      Header         : constant Ada.Streams.Stream_Element_Array := Read_Exact_Bytes (Conn, 2);
      Length_Code    : constant Natural := Natural (Header (Header'First + 1)) mod 16#80#;
      Payload_Length : Natural := Length_Code;
   begin
      if Length_Code = 126 then
         declare
            Bytes : constant Ada.Streams.Stream_Element_Array := Read_Exact_Bytes (Conn, 2);
         begin
            Payload_Length :=
              Natural (Bytes (Bytes'First)) * 256
              + Natural (Bytes (Bytes'First + 1));
            if Payload_Length <= 125 then
               raise Web.Errors.Protocol_Error with "non-minimal websocket length";
            end if;
         end;
      elsif Length_Code = 127 then
         raise Web.Errors.Protocol_Error with "oversized websocket frame";
      end if;

      Validate_Frame_Before_Payload (Header, Payload_Length);

      if Payload_Length > Max_Size then
         raise Web.Errors.Protocol_Error with "oversized websocket message";
      end if;

      declare
         Mask : constant Ada.Streams.Stream_Element_Array := Read_Exact_Bytes (Conn, 4);
         Payload_Data : constant Ada.Streams.Stream_Element_Array :=
           Read_Exact_Bytes (Conn, Payload_Length);
      begin
         return Decode_Received_Payload (Header, Payload_Length, Mask, Payload_Data);
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
