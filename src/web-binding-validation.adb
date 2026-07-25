with Web.Binding.Paths;

package body Web.Binding.Validation is

   use Web.Binding.Errors;

   procedure Reset (P : out Presentation) is
   begin
      P.Used := 0;
   end Reset;

   procedure Append_Entry
     (P      : in out Presentation;
      Origin : Issue_Origin;
      Field  : String;
      Key    : String;
      Path   : String) is
   begin
      if P.Used >= Max_Entries then
         return;
      end if;
      P.Used := P.Used + 1;
      P.Entries (P.Used) :=
        (Origin => Origin,
         Field  => Field_Strings.To_Bounded_String (Field, Drop => Ada.Strings.Right),
         Key    => Key_Strings.To_Bounded_String (Key, Drop => Ada.Strings.Right),
         Path   => Path_Strings.To_Bounded_String (Path, Drop => Ada.Strings.Right));
   end Append_Entry;

   procedure Add_Decoding_Errors
     (P : in out Presentation; Errors : Web.Binding.Errors.Error_Collection) is
   begin
      for I in 1 .. Natural (Length (Errors)) loop
         declare
            E : constant Decoding_Error := Element (Errors, I);
         begin
            Append_Entry
              (P,
               From_Decoding,
               Web.Binding.Paths.Last_Name (E.Path),
               Id_Key (E.Id),
               Web.Binding.Paths.Render (E.Path));
         end;
      end loop;
   end Add_Decoding_Errors;

   procedure Add_Validation_Issue
     (P     : in out Presentation;
      Field : String;
      Code  : String;
      Path  : String := "") is
   begin
      Append_Entry (P, From_Validation, Field, Code, Path);
   end Add_Validation_Issue;

   function Count (P : Presentation) return Natural is (P.Used);

   function Origin_Of (P : Presentation; Index : Positive) return Issue_Origin is
     (P.Entries (Index).Origin);

   function Field_Of (P : Presentation; Index : Positive) return String is
     (Field_Strings.To_String (P.Entries (Index).Field));

   function Key_Of (P : Presentation; Index : Positive) return String is
     (Key_Strings.To_String (P.Entries (Index).Key));

   function Path_Of (P : Presentation; Index : Positive) return String is
     (Path_Strings.To_String (P.Entries (Index).Path));

   function Decoding_Count (P : Presentation) return Natural is
      N : Natural := 0;
   begin
      for I in 1 .. P.Used loop
         if P.Entries (I).Origin = From_Decoding then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Decoding_Count;

   function Validation_Count (P : Presentation) return Natural is
     (P.Used - Decoding_Count (P));

end Web.Binding.Validation;
