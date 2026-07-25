with Ada.Strings.Bounded;
with Ada.Strings.Unbounded;
with Web.Binding.Errors;
with Web.Binding.Policies;

--  Forms integration adapter.
--
--  No Forms sibling exists yet, so this is the narrow contract a form layer will
--  consume, with an in-place implementation usable directly. It tracks the
--  submission lifecycle, retains submitted raw values for safe re-rendering
--  subject to sensitivity (a secret field's value is never retained -- passwords,
--  tokens and CSRF secrets stay blank), and converts a bind result's structured
--  errors into per-field and non-field form errors by their leaf path name.
--  Forms never reparse the request: they consume the binding output.
package Web.Binding.Forms is

   type Submission_State is
     (Not_Submitted,
      Decode_Failed,
      Decoded,
      Validation_Failed,
      Validated);

   Max_Fields      : constant := 128;
   Max_Form_Errors : constant := 64;
   Max_Name        : constant := 128;

   package Name_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Name);

   type Form is limited private;

   --  Reset to an unsubmitted form.
   --  @param F The form.
   procedure Reset (F : out Form);

   --  Mark the form submitted (a POST arrived).
   --  @param F The form.
   procedure Begin_Submission (F : in out Form);

   --  Register a field's submitted raw value, retained per sensitivity. Public
   --  values are retained for re-rendering; Private and Secret values are not
   --  retained (a re-render shows them blank).
   --  @param F The form.
   --  @param Name The field id.
   --  @param Value The submitted raw value.
   --  @param Sensitivity The field sensitivity.
   procedure Record_Field
     (F           : in out Form;
      Name        : String;
      Value       : String;
      Sensitivity : Web.Binding.Policies.Sensitivity :=
        Web.Binding.Policies.Public_Value);

   --  Import a bind result's errors, attaching each to a recorded field by its
   --  leaf path name, or as a non-field (form-level) error.
   --  @param F The form.
   --  @param Errors The decoding errors.
   procedure Import_Errors
     (F : in out Form; Errors : Web.Binding.Errors.Error_Collection);

   --  Transition after decoding: Decoded if no errors, else Decode_Failed.
   --  @param F The form.
   procedure Finish_Decoding (F : in out Form);

   --  Transition after semantic validation.
   --  @param F The form.
   --  @param Valid Whether validation passed.
   procedure Finish_Validation (F : in out Form; Valid : Boolean);

   --  The submission state.
   --  @param F The form.
   --  @return The state.
   function State (F : Form) return Submission_State;

   --  Whether the form was submitted.
   --  @param F The form.
   --  @return True if submitted.
   function Was_Submitted (F : Form) return Boolean;

   --  The retained raw value of a field for re-rendering ("" if not retained).
   --  @param F The form.
   --  @param Name The field id.
   --  @return The retained value.
   function Field_Value (F : Form; Name : String) return String;

   --  Whether a field's value was retained (false for secrets / unknown).
   --  @param F The form.
   --  @param Name The field id.
   --  @return True if retained.
   function Field_Retained (F : Form; Name : String) return Boolean;

   --  Whether a field has an error.
   --  @param F The form.
   --  @param Name The field id.
   --  @return True if a field error is attached.
   function Field_Has_Error (F : Form; Name : String) return Boolean;

   --  The first error id attached to a field.
   --  @param F The form.
   --  @param Name The field id.
   --  @return The error id (internal.decoder_failure if none).
   function Field_Error
     (F : Form; Name : String) return Web.Binding.Errors.Error_Id;

   --  The number of non-field (form-level) errors.
   --  @param F The form.
   --  @return The count.
   function Non_Field_Errors (F : Form) return Natural;

   --  The total number of imported errors.
   --  @param F The form.
   --  @return The count.
   function Error_Count (F : Form) return Natural;

private

   type Field_Entry is record
      Name     : Name_Strings.Bounded_String;
      Value    : Ada.Strings.Unbounded.Unbounded_String;
      Retained : Boolean := False;
   end record;

   type Field_Array is array (1 .. Max_Fields) of Field_Entry;

   type Error_Entry is record
      Field    : Name_Strings.Bounded_String;
      Id       : Web.Binding.Errors.Error_Id :=
        Web.Binding.Errors.Internal_Decoder_Failure;
      Is_Field : Boolean := False;
   end record;

   type Error_Array is array (1 .. Max_Form_Errors) of Error_Entry;

   type Form is limited record
      State_V    : Submission_State := Not_Submitted;
      Submitted  : Boolean := False;
      Field_Count : Natural := 0;
      Fields     : Field_Array;
      Err_Count  : Natural := 0;
      Errors     : Error_Array;
   end record;

end Web.Binding.Forms;
