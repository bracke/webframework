with Ada.Characters.Handling;

package body Web.Binding.Decoders.UUID_Decoders is

   use Web.Binding.Errors;

   Hyphen_Positions : constant array (1 .. 4) of Positive := [9, 14, 19, 24];

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.uuid"),
         Expected_Type => To_Identifier ("uuid"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function Is_Hyphen_Position (Pos : Positive) return Boolean is
   begin
      for P of Hyphen_Positions loop
         if P = Pos then
            return True;
         end if;
      end loop;
      return False;
   end Is_Hyphen_Position;

   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result
   is
      Normalized : String (1 .. 36);
   begin
      if Text'Length /= 36 then
         return Results.Make_Failure
           (Single_Error (Make_Error (Decode_Invalid_UUID, Path, Source)));
      end if;

      for Offset in 0 .. 35 loop
         declare
            C   : constant Character := Text (Text'First + Offset);
            Pos : constant Positive := Offset + 1;
         begin
            if Is_Hyphen_Position (Pos) then
               if C /= '-' then
                  return Results.Make_Failure
                    (Single_Error
                       (Make_Error (Decode_Invalid_UUID, Path, Source)));
               end if;
               Normalized (Pos) := '-';
            elsif Ada.Characters.Handling.Is_Hexadecimal_Digit (C) then
               Normalized (Pos) := Ada.Characters.Handling.To_Lower (C);
            else
               return Results.Make_Failure
                 (Single_Error
                    (Make_Error (Decode_Invalid_UUID, Path, Source)));
            end if;
         end;
      end loop;

      return Results.Make_Success ((Text => Normalized));
   end Decode;

   function Image (Value : UUID_Value) return String is
   begin
      return Value.Text;
   end Image;

end Web.Binding.Decoders.UUID_Decoders;
