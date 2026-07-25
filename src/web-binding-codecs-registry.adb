package body Web.Binding.Codecs.Registry is

   use Ids;
   package MT renames Web.Binding.Media_Types;

   function Id_Of (S : String) return Codec_Id is
     (To_Bounded_String (S, Drop => Ada.Strings.Right));

   procedure Reset (B : out Builder) is
   begin
      B.Data.Count := 0;
      B.Data.Missing := Reject_Missing;
      B.Data.Default_Id := Null_Bounded_String;
   end Reset;

   procedure Append (B : in out Builder; E : Reg_Entry) is
   begin
      if B.Data.Count < Max_Codecs then
         B.Data.Count := B.Data.Count + 1;
         B.Data.Entries (B.Data.Count) := E;
      end if;
   end Append;

   procedure Register_Exact
     (B : in out Builder; Id : String; Main : String; Sub : String) is
   begin
      Append (B,
         (Kind => K_Exact, Main => Id_Of (Main), Sub => Id_Of (Sub),
          Suffix => Null_Bounded_String, Id => Id_Of (Id)));
   end Register_Exact;

   procedure Register_Suffix (B : in out Builder; Id : String; Suffix : String)
   is
   begin
      Append (B,
         (Kind => K_Suffix, Main => Null_Bounded_String,
          Sub => Null_Bounded_String, Suffix => Id_Of (Suffix),
          Id => Id_Of (Id)));
   end Register_Suffix;

   procedure Register_Wildcard (B : in out Builder; Id : String; Main : String)
   is
   begin
      Append (B,
         (Kind => K_Wildcard, Main => Id_Of (Main),
          Sub => Null_Bounded_String, Suffix => Null_Bounded_String,
          Id => Id_Of (Id)));
   end Register_Wildcard;

   procedure Set_Missing
     (B : in out Builder; Policy : Missing_Policy; Default_Id : String := "") is
   begin
      B.Data.Missing := Policy;
      B.Data.Default_Id := Id_Of (Default_Id);
   end Set_Missing;

   --  The comparison key that must be unique within a kind.
   function Key (E : Reg_Entry) return String is
   begin
      case E.Kind is
         when K_Exact    => return To_String (E.Main) & "/" & To_String (E.Sub);
         when K_Suffix   => return To_String (E.Suffix);
         when K_Wildcard => return To_String (E.Main);
      end case;
   end Key;

   function Valid_Wildcard_Main (Main : String) return Boolean is
   begin
      if Main = "*" then
         return True;
      end if;
      if Main'Length = 0 then
         return False;
      end if;
      for C of Main loop
         case C is
            when 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '-' | '+' =>
               null;
            when others =>
               return False;
         end case;
      end loop;
      return True;
   end Valid_Wildcard_Main;

   procedure Freeze
     (B : Builder; R : out Registry; Status : out Freeze_Status) is
   begin
      R.Data := B.Data;
      Status := Frozen_Ok;

      if B.Data.Count > Max_Codecs then
         Status := Too_Many_Codecs;
         return;
      end if;

      for I in 1 .. B.Data.Count loop
         if B.Data.Entries (I).Kind = K_Wildcard
           and then not Valid_Wildcard_Main (To_String (B.Data.Entries (I).Main))
         then
            Status := Invalid_Wildcard;
            return;
         end if;
      end loop;

      for I in 1 .. B.Data.Count loop
         for J in I + 1 .. B.Data.Count loop
            if B.Data.Entries (I).Kind = B.Data.Entries (J).Kind
              and then Key (B.Data.Entries (I)) = Key (B.Data.Entries (J))
            then
               Status := Ambiguous_Patterns;
               return;
            end if;
         end loop;
      end loop;
   end Freeze;

   function Find
     (R : Registry; Kind : Kind_Type; K : String) return Selection is
   begin
      for I in 1 .. R.Data.Count loop
         if R.Data.Entries (I).Kind = Kind
           and then Key (R.Data.Entries (I)) = K
         then
            return (Matched => True, Id => R.Data.Entries (I).Id);
         end if;
      end loop;
      return (Matched => False);
   end Find;

   function Select_Codec
     (R : Registry; M : Web.Binding.Media_Types.Media_Type) return Selection
   is
      Main : constant String := MT.Tokens.To_String (M.Main);
      Sub  : constant String := MT.Tokens.To_String (M.Sub);
      Exact : constant Selection := Find (R, K_Exact, Main & "/" & Sub);
   begin
      if not MT.Is_Valid (M) then
         return (Matched => False);
      end if;
      if Exact.Matched then
         return Exact;
      end if;
      if MT.Has_Suffix (M) then
         declare
            Suf : constant Selection :=
              Find (R, K_Suffix, MT.Tokens.To_String (M.Suffix));
         begin
            if Suf.Matched then
               return Suf;
            end if;
         end;
      end if;
      declare
         By_Type : constant Selection := Find (R, K_Wildcard, Main);
      begin
         if By_Type.Matched then
            return By_Type;
         end if;
      end;
      return Find (R, K_Wildcard, "*");
   end Select_Codec;

   function Missing_Selection (R : Registry) return Selection is
   begin
      if R.Data.Missing = Use_Default and then Length (R.Data.Default_Id) > 0 then
         return (Matched => True, Id => R.Data.Default_Id);
      end if;
      return (Matched => False);
   end Missing_Selection;

   function Missing (R : Registry) return Missing_Policy is
     (R.Data.Missing);

end Web.Binding.Codecs.Registry;
