with Ada.Characters.Handling;

package body Web.Binding.Decoders.Float_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.float"),
         Expected_Type => To_Identifier ("float"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   --  Whether Text matches a strict decimal float grammar:
   --  [sign] digit+ ['.' digit+] [('e'|'E') [sign] digit+].
   function Valid_Syntax (Text : String) return Boolean is
      I    : Integer := Text'First;
      Last : constant Integer := Text'Last;

      function Take_Digits return Boolean is
         Start : constant Integer := I;
      begin
         while I <= Last and then Text (I) in '0' .. '9' loop
            I := I + 1;
         end loop;
         return I > Start;
      end Take_Digits;

   begin
      if Text'Length = 0 then
         return False;
      end if;
      if Text (I) in '+' | '-' then
         I := I + 1;
      end if;
      if not Take_Digits then
         return False;
      end if;
      if I <= Last and then Text (I) = '.' then
         I := I + 1;
         if not Take_Digits then
            return False;
         end if;
      end if;
      if I <= Last and then Text (I) in 'e' | 'E' then
         I := I + 1;
         if I <= Last and then Text (I) in '+' | '-' then
            I := I + 1;
         end if;
         if not Take_Digits then
            return False;
         end if;
      end if;
      return I > Last;
   end Valid_Syntax;

   --  Whether Text (minus an optional sign) is a non-finite word.
   function Is_Non_Finite (Text : String) return Boolean is
      First : Integer := Text'First;
   begin
      if First <= Text'Last and then Text (First) in '+' | '-' then
         First := First + 1;
      end if;
      declare
         Word : String (First .. Text'Last);
      begin
         for I in Word'Range loop
            Word (I) := Ada.Characters.Handling.To_Lower (Text (I));
         end loop;
         return Word = "nan" or else Word = "inf" or else Word = "infinity";
      end;
   end Is_Non_Finite;

   function Fail
     (Id : Error_Id; Path : Web.Binding.Paths.Field_Path; Source : Source_Kind)
      return Result is
   begin
      return Results.Make_Failure
        (Single_Error (Make_Error (Id, Path, Source)));
   end Fail;

   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result is
   begin
      if Is_Non_Finite (Text) then
         return Fail (Decode_Non_Finite_Float, Path, Source);
      end if;
      if not Valid_Syntax (Text) then
         return Fail (Decode_Invalid_Float, Path, Source);
      end if;

      --  Defensive boundary: valid syntax may still overflow the target range,
      --  which Target'Value signals by raising. Convert it, do not propagate.
      begin
         return Results.Make_Success (Target'Value (Text));
      exception
         when others =>
            return Fail (Decode_Non_Finite_Float, Path, Source);
      end;
   end Decode;

end Web.Binding.Decoders.Float_Decoders;
