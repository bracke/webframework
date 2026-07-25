package body Web.Binding.Decoders.Base64_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.base64"),
         Expected_Type => To_Identifier ("base64"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   --  The 6-bit value of a Base64 character, or -1 if not in the alphabet.
   function Sextet (C : Character; Which : Alphabet) return Integer is
   begin
      case C is
         when 'A' .. 'Z' => return Character'Pos (C) - Character'Pos ('A');
         when 'a' .. 'z' => return 26 + Character'Pos (C) - Character'Pos ('a');
         when '0' .. '9' => return 52 + Character'Pos (C) - Character'Pos ('0');
         when '+' => return (if Which = Standard then 62 else -1);
         when '/' => return (if Which = Standard then 63 else -1);
         when '-' => return (if Which = URL_Safe then 62 else -1);
         when '_' => return (if Which = URL_Safe then 63 else -1);
         when others => return -1;
      end case;
   end Sextet;

   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result
   is
      Out_Bytes : String (1 .. Text'Length);
      Out_Len   : Natural := 0;
      Acc       : Natural := 0;
      Bits      : Natural := 0;
      Pad       : Natural := 0;
      Data      : Natural := 0;

      function Invalid return Result is
        (Results.Make_Failure
           (Single_Error (Make_Error (Decode_Invalid_Base64, Path, Source))));

   begin
      for I in Text'Range loop
         declare
            C : constant Character := Text (I);
         begin
            if C = '=' then
               Pad := Pad + 1;
               if Pad > 2 then
                  return Invalid;
               end if;
            else
               if Pad > 0 then
                  return Invalid;  --  data after padding
               end if;
               declare
                  V : constant Integer := Sextet (C, Settings.Which);
               begin
                  if V < 0 then
                     return Invalid;
                  end if;
                  Data := Data + 1;
                  Acc := Acc * 64 + V;
                  Bits := Bits + 6;
                  if Bits >= 8 then
                     Bits := Bits - 8;
                     Out_Len := Out_Len + 1;
                     Out_Bytes (Out_Len) :=
                       Character'Val ((Acc / (2 ** Bits)) mod 256);
                     --  Retain only the still-pending low bits so the
                     --  accumulator cannot grow without bound.
                     Acc := Acc mod (2 ** Bits);
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Validate the padding against the data-character count.
      declare
         Rem_Quad    : constant Natural := Data mod 4;
         Needed_Pad  : constant Natural :=
           (case Rem_Quad is when 0 => 0, when 2 => 2, when 3 => 1,
                             when others => 99);
      begin
         if Rem_Quad = 1 then
            return Invalid;
         end if;
         if Settings.Require_Padding then
            if (Data + Pad) mod 4 /= 0 or else Pad /= Needed_Pad then
               return Invalid;
            end if;
         elsif Pad /= 0 and then Pad /= Needed_Pad then
            return Invalid;
         end if;
      end;

      if Byte_Count (Out_Len) > Byte_Count (Bounded.Max_Length) then
         declare
            Params : Error_Parameters;
         begin
            Params.Has_Actual := True;
            Params.Actual := Long_Long_Integer (Out_Len);
            Params.Has_Maximum := True;
            Params.Maximum := Long_Long_Integer (Bounded.Max_Length);
            return Results.Make_Failure
              (Single_Error
                 (Make_Error (Decode_Value_Too_Long, Path, Source,
                              Decode_Origin, Parameters => Params)));
         end;
      end if;

      return Results.Make_Success
        (Bounded.To_Bounded_String (Out_Bytes (1 .. Out_Len)));
   end Decode;

end Web.Binding.Decoders.Base64_Decoders;
