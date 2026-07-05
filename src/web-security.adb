with Ada.Streams;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with CryptoLib.Errors;
with CryptoLib.Random;
with SSH_Lib.Protocol.Buffers;
with Web.Errors;

package body Web.Security is
   use Ada.Strings.Unbounded;
   use type CryptoLib.Errors.Status;

   Alphabet      : constant String := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

   protected Random_Generator is
      procedure Fill
        (Buffer : out Ada.Streams.Stream_Element_Array;
         Status : out CryptoLib.Errors.Status);
   private
      Source : CryptoLib.Random.Random_Source;
      Ready  : Boolean := False;
   end Random_Generator;

   protected body Random_Generator is
      procedure Fill
        (Buffer : out Ada.Streams.Stream_Element_Array;
         Status : out CryptoLib.Errors.Status) is
      begin
         if not Ready then
            CryptoLib.Random.Initialize_Production (Source);
            Ready := True;
         end if;

         Status := CryptoLib.Random.Fill (Source, Buffer);
      end Fill;
   end Random_Generator;

   function Is_Visible_ASCII (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Ch of Value loop
         if Character'Pos (Ch) < 33 or else Character'Pos (Ch) > 126 then
            return False;
         end if;
      end loop;

      return True;
   end Is_Visible_ASCII;

   function Is_Decimal_Port (Value : String) return Boolean is
      Port_Value : Natural := 0;
   begin
      if Value'Length = 0 or else Value'Length > 5 then
         return False;
      end if;

      for Ch of Value loop
         if Ch not in '0' .. '9' then
            return False;
         end if;

         Port_Value := Port_Value * 10 + Character'Pos (Ch) - Character'Pos ('0');
         if Port_Value > 65_535 then
            return False;
         end if;
      end loop;

      return Port_Value > 0;
   end Is_Decimal_Port;

   function Is_Valid_Host_Name (Value : String) return Boolean is
      Last_Was_Dot : Boolean := False;
   begin
      if not Is_Visible_ASCII (Value) then
         return False;
      end if;

      if Value (Value'First) = '.' or else Value (Value'Last) = '.' then
         return False;
      end if;

      for Ch of Value loop
         if Ch = '.' then
            if Last_Was_Dot then
               return False;
            end if;
            Last_Was_Dot := True;
         elsif Ch in 'a' .. 'z'
           or else Ch in 'A' .. 'Z'
           or else Ch in '0' .. '9'
           or else Ch = '-'
         then
            Last_Was_Dot := False;
         else
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Host_Name;

   function Is_Valid_IPv6_Literal (Value : String) return Boolean is
      Colon_Count : Natural := 0;
   begin
      if Value'Length < 3
        or else Value (Value'First) /= '['
        or else Value (Value'Last) /= ']'
      then
         return False;
      end if;

      for Index_Value in Value'First + 1 .. Value'Last - 1 loop
         declare
            Ch : constant Character := Value (Index_Value);
         begin
            if Ch = ':' then
               Colon_Count := Colon_Count + 1;
            elsif Ch in 'a' .. 'f'
              or else Ch in 'A' .. 'F'
              or else Ch in '0' .. '9'
              or else Ch = '.'
            then
               null;
            else
               return False;
            end if;
         end;
      end loop;

      return Colon_Count >= 2;
   end Is_Valid_IPv6_Literal;

   function Normalize_Authority (Value : String) return String is
      Port_Separator : Natural := 0;
      Host_Text : Unbounded_String;
      Port_Text : Unbounded_String;
   begin
      if not Is_Visible_ASCII (Value)
        or else Ada.Strings.Fixed.Index (Value, "@") > 0
        or else Ada.Strings.Fixed.Index (Value, "/") > 0
        or else Ada.Strings.Fixed.Index (Value, "?") > 0
        or else Ada.Strings.Fixed.Index (Value, "#") > 0
      then
         return "";
      end if;

      if Value (Value'First) = '[' then
         declare
            Close_Bracket : constant Natural := Ada.Strings.Fixed.Index (Value, "]");
         begin
            if Close_Bracket = 0 then
               return "";
            end if;

            Host_Text := To_Unbounded_String (Value (Value'First .. Close_Bracket));
            if Close_Bracket < Value'Last then
               if Value (Close_Bracket + 1) /= ':' then
                  return "";
               end if;
               Port_Text := To_Unbounded_String (Value (Close_Bracket + 2 .. Value'Last));
            end if;
         end;
      else
         for Index_Value in reverse Value'Range loop
            if Value (Index_Value) = ':' then
               Port_Separator := Index_Value;
               exit;
            end if;
         end loop;

         if Port_Separator = 0 then
            Host_Text := To_Unbounded_String (Value);
         else
            Host_Text := To_Unbounded_String (Value (Value'First .. Port_Separator - 1));
            Port_Text := To_Unbounded_String (Value (Port_Separator + 1 .. Value'Last));
         end if;
      end if;

      declare
         Host_Value : constant String := To_String (Host_Text);
         Port_Value : constant String := To_String (Port_Text);
      begin
         if Host_Value'Length = 0 then
            return "";
         end if;

         if Host_Value (Host_Value'First) = '[' then
            if not Is_Valid_IPv6_Literal (Host_Value) then
               return "";
            end if;
         elsif not Is_Valid_Host_Name (Host_Value) then
            return "";
         end if;

         if Port_Value'Length > 0 and then not Is_Decimal_Port (Port_Value) then
            return "";
         end if;

         if Port_Value'Length > 0 then
            return Ada.Characters.Handling.To_Lower (Host_Value) & ":" & Port_Value;
         end if;

         return Ada.Characters.Handling.To_Lower (Host_Value);
      end;
   end Normalize_Authority;

   function Normalize_Origin (Value : String) return String is
      Separator : constant Natural := Ada.Strings.Fixed.Index (Value, "://");
   begin
      if Separator = 0 then
         return "";
      end if;

      declare
         Scheme_Text : constant String :=
           Ada.Characters.Handling.To_Lower (Value (Value'First .. Separator - 1));
         Authority_Text : constant String := Value (Separator + 3 .. Value'Last);
         Authority : constant String := Normalize_Authority (Authority_Text);
      begin
         if Scheme_Text /= "http" and then Scheme_Text /= "https" then
            return "";
         end if;

         if Authority'Length = 0 then
            return "";
         end if;

         return Scheme_Text & "://" & Authority;
      end;
   end Normalize_Origin;

   function Authority_Of_Origin (Value : String) return String is
      Origin_Value : constant String := Normalize_Origin (Value);
      Separator    : constant Natural := Ada.Strings.Fixed.Index (Origin_Value, "://");
   begin
      if Separator = 0 then
         return "";
      end if;

      return Origin_Value (Separator + 3 .. Origin_Value'Last);
   end Authority_Of_Origin;

   function Is_Safe_Path (Path : String) return Boolean is
   begin
      if Path'Length = 0 then
         return False;
      end if;

      if Path'Length >= 2 and then Path (Path'First .. Path'First + 1) = "//" then
         return False;
      end if;

      if Ada.Strings.Fixed.Index (Path, "..") /= 0 then
         return False;
      end if;

      for Ch of Path loop
         if Character'Pos (Ch) < 32
           or else Character'Pos (Ch) = 127
           or else Ch = '\'
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Safe_Path;

   function New_Session_Id return String is
      Buffer       : Ada.Streams.Stream_Element_Array (1 .. 32);
      Result       : Unbounded_String;
      Status       : CryptoLib.Errors.Status;
      Secret_Bytes : SSH_Lib.Protocol.Buffers.Packet_Buffer;
   begin
      Random_Generator.Fill (Buffer, Status);
      if Status /= CryptoLib.Errors.Ok then
         raise Web.Errors.Security_Error with "session id entropy unavailable";
      end if;

      Status := SSH_Lib.Protocol.Buffers.Set (Secret_Bytes, Buffer);
      if Status /= CryptoLib.Errors.Ok then
         raise Web.Errors.Security_Error with "session id entropy buffer unavailable";
      end if;

      for Byte_Value of SSH_Lib.Protocol.Buffers.To_Array (Secret_Bytes) loop
         Append (Result, Alphabet (Alphabet'First + Natural (Byte_Value) mod Alphabet'Length));
      end loop;

      SSH_Lib.Protocol.Buffers.Clear (Secret_Bytes);
      return To_String (Result);
   end New_Session_Id;

   function Is_Valid_Session_Id (Id : String) return Boolean is
   begin
      if Id'Length /= 32 then
         return False;
      end if;

      for Ch of Id loop
         if Ada.Strings.Fixed.Index (Alphabet, String'(1 => Ch)) = 0 then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Session_Id;

   function Require_Allowed_Origin
     (Request        : Web.Request.Request_Type;
      Allowed_Origin : String) return Boolean
   is
      Origin : constant String := Web.Request.Header (Request, "Origin");
      Host   : constant String := Web.Request.Header (Request, "Host");
      Allowed_As_Origin : constant String := Normalize_Origin (Allowed_Origin);
      Allowed_Authority : constant String :=
        (if Allowed_As_Origin'Length > 0
         then Authority_Of_Origin (Allowed_As_Origin)
         else Normalize_Authority (Allowed_Origin));
   begin
      if Allowed_Origin'Length = 0 then
         return True;
      end if;

      if Allowed_Authority'Length = 0 then
         return False;
      end if;

      if Origin'Length > 0 then
         declare
            Request_Origin : constant String := Normalize_Origin (Origin);
         begin
            if Request_Origin'Length = 0 then
               return False;
            end if;

            if Allowed_As_Origin'Length > 0 then
               return Request_Origin = Allowed_As_Origin;
            end if;

            return Authority_Of_Origin (Request_Origin) = Allowed_Authority;
         end;
      end if;

      return Normalize_Authority (Host) = Allowed_Authority;
   end Require_Allowed_Origin;
end Web.Security;
