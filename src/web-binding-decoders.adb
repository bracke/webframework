package body Web.Binding.Decoders is

   function To_Identifier (Text : String) return Id_Strings.Bounded_String is
   begin
      return Id_Strings.To_Bounded_String (Text, Drop => Ada.Strings.Right);
   end To_Identifier;

   function Single_Error
     (Error : Web.Binding.Errors.Decoding_Error)
      return Web.Binding.Errors.Error_Collection
   is
      Result : Web.Binding.Errors.Error_Collection :=
        Web.Binding.Errors.Empty_Collection;
   begin
      Web.Binding.Errors.Append (Result, Error);
      return Result;
   end Single_Error;

   function Valid_UTF8 (Text : String) return Boolean is

      function Byte (I : Integer) return Natural is
        (Character'Pos (Text (I)));

      --  A continuation byte 10xxxxxx.
      function Cont (I : Integer) return Boolean is
        (I <= Text'Last and then Byte (I) in 16#80# .. 16#BF#);

      I  : Integer := Text'First;
      B0 : Natural;
   begin
      while I <= Text'Last loop
         B0 := Byte (I);
         if B0 <= 16#7F# then
            I := I + 1;
         elsif B0 in 16#C2# .. 16#DF# then
            if not Cont (I + 1) then
               return False;
            end if;
            I := I + 2;
         elsif B0 = 16#E0# then
            --  Second byte A0..BF avoids the overlong three-byte range.
            if I + 1 > Text'Last or else Byte (I + 1) not in 16#A0# .. 16#BF#
              or else not Cont (I + 2)
            then
               return False;
            end if;
            I := I + 3;
         elsif B0 in 16#E1# .. 16#EC# or else B0 in 16#EE# .. 16#EF# then
            if not Cont (I + 1) or else not Cont (I + 2) then
               return False;
            end if;
            I := I + 3;
         elsif B0 = 16#ED# then
            --  Second byte 80..9F excludes the surrogate range D800..DFFF.
            if I + 1 > Text'Last or else Byte (I + 1) not in 16#80# .. 16#9F#
              or else not Cont (I + 2)
            then
               return False;
            end if;
            I := I + 3;
         elsif B0 = 16#F0# then
            --  Second byte 90..BF avoids the overlong four-byte range.
            if I + 1 > Text'Last or else Byte (I + 1) not in 16#90# .. 16#BF#
              or else not Cont (I + 2) or else not Cont (I + 3)
            then
               return False;
            end if;
            I := I + 4;
         elsif B0 in 16#F1# .. 16#F3# then
            if not Cont (I + 1) or else not Cont (I + 2)
              or else not Cont (I + 3)
            then
               return False;
            end if;
            I := I + 4;
         elsif B0 = 16#F4# then
            --  Second byte 80..8F caps the value at U+10FFFF.
            if I + 1 > Text'Last or else Byte (I + 1) not in 16#80# .. 16#8F#
              or else not Cont (I + 2) or else not Cont (I + 3)
            then
               return False;
            end if;
            I := I + 4;
         else
            return False;
         end if;
      end loop;
      return True;
   end Valid_UTF8;

end Web.Binding.Decoders;
