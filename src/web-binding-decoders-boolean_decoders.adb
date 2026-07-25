with Ada.Characters.Handling;

package body Web.Binding.Decoders.Boolean_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.boolean"),
         Expected_Type => To_Identifier ("boolean"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   --  ASCII-lowercase a string (locale independent).
   function Fold (Text : String) return String is
      Result : String (Text'Range);
   begin
      for I in Text'Range loop
         Result (I) := Ada.Characters.Handling.To_Lower (Text (I));
      end loop;
      return Result;
   end Fold;

   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result
   is
      Candidate : constant String :=
        (if Settings.Case_Insensitive then Fold (Text) else Text);

      --  Whether Candidate equals the given literal under the active policy.
      function Is_Literal (Literal : String) return Boolean is
      begin
         return Candidate =
           (if Settings.Case_Insensitive then Fold (Literal) else Literal);
      end Is_Literal;

      --  Match against an enabled set; returns whether it matched and the value.
      function Matches
        (Set : Literal_Set; True_Word, False_Word : String;
         Value : out Boolean) return Boolean is
      begin
         Value := False;
         if not Settings.Accept_Sets (Set) then
            return False;
         end if;
         if Is_Literal (True_Word) then
            Value := True;
            return True;
         elsif Is_Literal (False_Word) then
            Value := False;
            return True;
         end if;
         return False;
      end Matches;

      Value : Boolean;
   begin
      if Matches (True_False, "true", "false", Value)
        or else Matches (One_Zero, "1", "0", Value)
        or else Matches (Yes_No, "yes", "no", Value)
        or else Matches (On_Off, "on", "off", Value)
      then
         return Results.Make_Success (Value);
      end if;

      return Results.Make_Failure
        (Single_Error
           (Make_Error
              (Id     => Decode_Invalid_Boolean,
               Path   => Path,
               Source => Source)));
   end Decode;

end Web.Binding.Decoders.Boolean_Decoders;
