with Ada.Characters.Handling;

package body Web.Binding.Decoders.Enum_Decoders is

   use Web.Binding.Errors;
   use Wire_Strings;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.enum"),
         Expected_Type => To_Identifier ("enum"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function Fold (Text : String) return String is
      Result : String (Text'Range);
   begin
      for I in Text'Range loop
         Result (I) := Ada.Characters.Handling.To_Lower (Text (I));
      end loop;
      return Result;
   end Fold;

   function Empty_Table
     (Folding : Case_Mode := Case_Sensitive) return Mapping_Table
   is
      Result : Mapping_Table;
   begin
      Result.Folding := Folding;
      return Result;
   end Empty_Table;

   function Add
     (Table      : Mapping_Table;
      Wire       : String;
      Value      : Target;
      Deprecated : Boolean := False) return Mapping_Table
   is
      Result : Mapping_Table := Table;
   begin
      if Result.Count < Max_Mappings then
         Result.Count := Result.Count + 1;
         Result.Entries (Result.Count) :=
           (Wire       => To_Bounded_String (Wire, Drop => Ada.Strings.Right),
            Value      => Value,
            Deprecated => Deprecated);
      end if;
      return Result;
   end Add;

   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind;
      Table  : Mapping_Table) return Result
   is
      Insensitive : constant Boolean := Table.Folding = ASCII_Case_Insensitive;
      Candidate   : constant String := (if Insensitive then Fold (Text) else Text);

      function Matches (Wire : String) return Boolean is
      begin
         return Candidate = (if Insensitive then Fold (Wire) else Wire);
      end Matches;

   begin
      for I in 1 .. Table.Count loop
         if Matches (To_String (Table.Entries (I).Wire)) then
            return Results.Make_Success (Table.Entries (I).Value);
         end if;
      end loop;

      --  Not found: surface the allowed wires (up to the parameter capacity).
      declare
         Params : Error_Parameters;
      begin
         Params.Expected_Type := Text_Param ("enum");
         for I in 1 .. Table.Count loop
            exit when Params.Allowed_Count >= Max_Allowed_Values;
            Params.Allowed_Count := Params.Allowed_Count + 1;
            Params.Allowed (Params.Allowed_Count) :=
              Text_Param (To_String (Table.Entries (I).Wire));
         end loop;
         return Results.Make_Failure
           (Single_Error
              (Make_Error (Decode_Invalid_Enum, Path, Source, Decode_Origin,
                           Parameters => Params)));
      end;
   end Decode;

end Web.Binding.Decoders.Enum_Decoders;
