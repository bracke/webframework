package body Web.Binding.Decoders.Modular_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.modular"),
         Expected_Type => To_Identifier ("modular"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function Base_Value (Base : Radix) return Long_Long_Integer is
   begin
      case Base is
         when Decimal     => return 10;
         when Hexadecimal => return 16;
         when Octal       => return 8;
         when Binary      => return 2;
      end case;
   end Base_Value;

   function Digit_Value (C : Character; Base : Radix) return Integer is
      Limit : constant Integer := Integer (Base_Value (Base));
      Value : Integer;
   begin
      case C is
         when '0' .. '9' => Value := Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => Value := 10 + Character'Pos (C) - Character'Pos ('a');
         when 'A' .. 'F' => Value := 10 + Character'Pos (C) - Character'Pos ('A');
         when others     => return -1;
      end case;
      return (if Value < Limit then Value else -1);
   end Digit_Value;

   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result
   is
      First : Integer := Text'First;
      Last  : Integer := Text'Last;

      function Invalid return Result is
        (Results.Make_Failure
           (Single_Error (Make_Error (Decode_Invalid_Integer, Path, Source))));

      function Overflow return Result is
         Params : Error_Parameters;
      begin
         Params.Has_Maximum := True;
         Params.Maximum := Long_Long_Integer (Target'Last);
         Params.Has_Minimum := True;
         Params.Minimum := 0;
         return Results.Make_Failure
           (Single_Error
              (Make_Error (Decode_Integer_Out_Of_Range, Path, Source,
                           Decode_Origin, Parameters => Params)));
      end Overflow;

   begin
      if Settings.Allow_Whitespace then
         while First <= Last and then Text (First) = ' ' loop
            First := First + 1;
         end loop;
         while Last >= First and then Text (Last) = ' ' loop
            Last := Last - 1;
         end loop;
      end if;

      if First > Last then
         return Invalid;
      end if;

      if not Settings.Allow_Leading_Zero
        and then Text (First) = '0' and then First < Last
      then
         return Invalid;
      end if;

      declare
         Mag      : Long_Long_Integer := 0;
         Any      : Boolean := False;
         Prev_Sep : Boolean := False;
         B        : constant Long_Long_Integer := Base_Value (Settings.Base);
         Idx      : Integer := First;
      begin
         while Idx <= Last loop
            declare
               C : constant Character := Text (Idx);
               D : Integer;
            begin
               if C = '_' and then Settings.Allow_Separators then
                  if not Any or else Prev_Sep or else Idx = Last then
                     return Invalid;
                  end if;
                  Prev_Sep := True;
               else
                  D := Digit_Value (C, Settings.Base);
                  if D < 0 then
                     return Invalid;
                  end if;
                  if Mag > (Long_Long_Integer'Last - Long_Long_Integer (D)) / B
                  then
                     return Overflow;
                  end if;
                  Mag := Mag * B + Long_Long_Integer (D);
                  Any := True;
                  Prev_Sep := False;
               end if;
            end;
            Idx := Idx + 1;
         end loop;

         if not Any then
            return Invalid;
         end if;
         if Mag > Long_Long_Integer (Target'Last) then
            return Overflow;
         end if;
         return Results.Make_Success (Target (Mag));
      end;
   end Decode;

end Web.Binding.Decoders.Modular_Decoders;
