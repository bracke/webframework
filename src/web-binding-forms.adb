with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Binding.Paths;

package body Web.Binding.Forms is

   use Web.Binding.Errors;
   use Web.Binding.Policies;
   use Name_Strings;

   procedure Reset (F : out Form) is
   begin
      F.State_V := Not_Submitted;
      F.Submitted := False;
      F.Field_Count := 0;
      F.Err_Count := 0;
   end Reset;

   procedure Begin_Submission (F : in out Form) is
   begin
      F.Submitted := True;
   end Begin_Submission;

   --  The slot of a named field, or 0.
   function Slot_Of (F : Form; Name : String) return Natural is
   begin
      for I in 1 .. F.Field_Count loop
         if To_String (F.Fields (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Slot_Of;

   procedure Record_Field
     (F           : in out Form;
      Name        : String;
      Value       : String;
      Sensitivity : Web.Binding.Policies.Sensitivity := Public_Value)
   is
      Retain : constant Boolean := Sensitivity = Public_Value;
      Slot   : Natural := Slot_Of (F, Name);
   begin
      if Slot = 0 then
         if F.Field_Count >= Max_Fields then
            return;
         end if;
         F.Field_Count := F.Field_Count + 1;
         Slot := F.Field_Count;
         F.Fields (Slot).Name := To_Bounded_String (Name, Drop => Ada.Strings.Right);
      end if;
      F.Fields (Slot).Retained := Retain;
      F.Fields (Slot).Value :=
        (if Retain then To_Unbounded_String (Value) else Null_Unbounded_String);
   end Record_Field;

   procedure Import_Errors
     (F : in out Form; Errors : Web.Binding.Errors.Error_Collection) is
   begin
      for I in 1 .. Natural (Length (Errors)) loop
         exit when F.Err_Count >= Max_Form_Errors;
         declare
            E    : constant Decoding_Error := Element (Errors, I);
            Name : constant String := Web.Binding.Paths.Last_Name (E.Path);
            Is_F : constant Boolean := Name /= "" and then Slot_Of (F, Name) /= 0;
         begin
            F.Err_Count := F.Err_Count + 1;
            F.Errors (F.Err_Count) :=
              (Field => To_Bounded_String (Name, Drop => Ada.Strings.Right),
               Id => E.Id,
               Is_Field => Is_F);
         end;
      end loop;
   end Import_Errors;

   procedure Finish_Decoding (F : in out Form) is
   begin
      F.State_V := (if F.Err_Count > 0 then Decode_Failed else Decoded);
   end Finish_Decoding;

   procedure Finish_Validation (F : in out Form; Valid : Boolean) is
   begin
      F.State_V := (if Valid then Validated else Validation_Failed);
   end Finish_Validation;

   function State (F : Form) return Submission_State is (F.State_V);

   function Was_Submitted (F : Form) return Boolean is (F.Submitted);

   function Field_Value (F : Form; Name : String) return String is
      Slot : constant Natural := Slot_Of (F, Name);
   begin
      if Slot = 0 or else not F.Fields (Slot).Retained then
         return "";
      end if;
      return To_String (F.Fields (Slot).Value);
   end Field_Value;

   function Field_Retained (F : Form; Name : String) return Boolean is
      Slot : constant Natural := Slot_Of (F, Name);
   begin
      return Slot /= 0 and then F.Fields (Slot).Retained;
   end Field_Retained;

   function Field_Has_Error (F : Form; Name : String) return Boolean is
   begin
      for I in 1 .. F.Err_Count loop
         if F.Errors (I).Is_Field
           and then To_String (F.Errors (I).Field) = Name
         then
            return True;
         end if;
      end loop;
      return False;
   end Field_Has_Error;

   function Field_Error
     (F : Form; Name : String) return Web.Binding.Errors.Error_Id is
   begin
      for I in 1 .. F.Err_Count loop
         if F.Errors (I).Is_Field
           and then To_String (F.Errors (I).Field) = Name
         then
            return F.Errors (I).Id;
         end if;
      end loop;
      return Internal_Decoder_Failure;
   end Field_Error;

   function Non_Field_Errors (F : Form) return Natural is
      N : Natural := 0;
   begin
      for I in 1 .. F.Err_Count loop
         if not F.Errors (I).Is_Field then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Non_Field_Errors;

   function Error_Count (F : Form) return Natural is (F.Err_Count);

end Web.Binding.Forms;
