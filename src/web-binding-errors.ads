with Ada.Strings.Bounded;
with Web.Binding.Paths;

--  Structured, localization-ready decoding errors.
--
--  Error identity is a closed enumeration (Error_Id), never a free-form string:
--  the literal spelling is the stable, compatibility-sensitive localization key
--  (invariant BIND-005), and Id_Key renders the canonical dotted form. Errors
--  carry an exact structured path (BIND-006), a source classification, optional
--  source location, and bounded structured parameters suitable for localization.
--  Raw sensitive values are never stored here (BIND-011). Collections are
--  bounded and truncate deterministically (BIND-004).
package Web.Binding.Errors is

   pragma Preelaborate;

   --  The canonical error identifiers. Each literal's spelling IS its stable
   --  key (see Id_Key); kept in exact correspondence with the specification.
   --  binding.* identifiers.
   type Error_Id is
     (Binding_Missing,
      Binding_Duplicate,
      Binding_Empty_Not_Allowed,
      Binding_Unknown_Field,
      Binding_Source_Unavailable,
      Binding_Source_Already_Consumed,
      --  decode.*
      Decode_Invalid_UTF8,
      Decode_Invalid_Integer,
      Decode_Integer_Out_Of_Range,
      Decode_Invalid_Float,
      Decode_Non_Finite_Float,
      Decode_Invalid_Boolean,
      Decode_Invalid_UUID,
      Decode_Invalid_Date,
      Decode_Invalid_Time,
      Decode_Invalid_Datetime,
      Decode_Invalid_Enum,
      Decode_Invalid_Character,
      Decode_Invalid_Base64,
      Decode_Invalid_List,
      Decode_Too_Many_Items,
      Decode_Nesting_Too_Deep,
      Decode_Value_Too_Long,
      Decode_Invalid_URI,
      --  body.*
      Body_Missing_Content_Type,
      Body_Unsupported_Media_Type,
      Body_Invalid_Content_Type,
      Body_Too_Large,
      Body_Empty_Not_Allowed,
      Body_Codec_Not_Found,
      Body_Codec_Failure,
      --  json.*
      Json_Malformed,
      Json_Unexpected_Kind,
      Json_Missing_Member,
      Json_Duplicate_Member,
      Json_Unknown_Member,
      Json_Trailing_Content,
      Json_Number_Out_Of_Range,
      Json_Depth_Exceeded,
      Json_Token_Limit_Exceeded,
      --  form.*
      Form_Malformed_URL_Encoding,
      Form_Invalid_Percent_Escape,
      Form_Too_Many_Fields,
      Form_Field_Too_Large,
      --  multipart.*
      Multipart_Invalid_Boundary,
      Multipart_Malformed,
      Multipart_Too_Many_Parts,
      Multipart_Part_Headers_Too_Large,
      Multipart_Field_Too_Large,
      Multipart_Upload_Too_Large,
      Multipart_Missing_Name,
      Multipart_Invalid_Disposition,
      Multipart_Unexpected_File,
      Multipart_Expected_File,
      Multipart_Upload_Rejected,
      --  union.*
      Union_Missing_Discriminator,
      Union_Invalid_Discriminator,
      Union_Ambiguous_Alternative,
      Union_No_Matching_Alternative,
      --  internal.*
      Internal_Decoder_Failure,
      Internal_Binding_Definition_Error);

   --  The canonical dotted key for an identifier, e.g. Decode_Integer_Out_Of_Range
   --  renders "decode.integer_out_of_range". Derived deterministically from the
   --  literal spelling: the namespace is the text before the first underscore.
   --  @param Id The error identifier.
   --  @return The stable localization key.
   function Id_Key (Id : Error_Id) return String;

   --  Where an error arose, for response-status mapping and diagnostics.
   type Error_Origin is
     (Decode_Origin,
      Structural_Origin,
      Limit_Origin,
      Internal_Origin);

   --  Error classification, kept open for future levels.
   type Severity_Level is (Recoverable, Fatal);

   --  Optional source location. Each dimension is present only when the source
   --  can supply it; absent fields stay at their zero default.
   type Source_Location is record
      Has_Ordinal      : Boolean := False;
      Ordinal          : Parameter_Ordinal := 0;
      Has_Byte_Offset  : Boolean := False;
      Byte_Offset      : Offset_Count := 0;
      Has_Line         : Boolean := False;
      Line             : Line_Number := 0;
      Has_Column       : Boolean := False;
      Column           : Column_Number := 0;
      Has_Token_Offset : Boolean := False;
      Token_Offset     : Token_Count := 0;
      Has_Part         : Boolean := False;
      Part             : Part_Number := 0;
   end record;

   No_Location : constant Source_Location := (others => <>);

   package Param_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (128);

   subtype Param_Text is Param_Strings.Bounded_String;

   --  A bounded text parameter; the empty string means absent.
   --  @param Text The parameter text (truncated to the bound).
   --  @return The bounded parameter value.
   function Text_Param (Text : String) return Param_Text;

   Max_Allowed_Values : constant := 16;

   type Allowed_Array is array (1 .. Max_Allowed_Values) of Param_Text;

   --  Bounded structured parameters for localization. Numeric parameters carry a
   --  presence flag; text parameters are absent when empty. No raw sensitive
   --  value is ever placed here.
   type Error_Parameters is record
      Has_Minimum         : Boolean := False;
      Minimum             : Long_Long_Integer := 0;
      Has_Maximum         : Boolean := False;
      Maximum             : Long_Long_Integer := 0;
      Has_Actual          : Boolean := False;
      Actual              : Long_Long_Integer := 0;
      Has_Limit           : Boolean := False;
      Limit               : Long_Long_Integer := 0;
      Has_Duplicate_Count : Boolean := False;
      Duplicate_Count     : Long_Long_Integer := 0;
      Expected_Type       : Param_Text := Param_Strings.Null_Bounded_String;
      Actual_Kind         : Param_Text := Param_Strings.Null_Bounded_String;
      Media_Type          : Param_Text := Param_Strings.Null_Bounded_String;
      Allowed_Count       : Natural := 0;
      Allowed             : Allowed_Array :=
        [others => Param_Strings.Null_Bounded_String];
   end record;

   No_Parameters : constant Error_Parameters := (others => <>);

   --  A single decoding error. Every field-specific error carries an exact path.
   --  Id and Source carry placeholder defaults only so the bounded array backing
   --  an Error_Collection is trivially default-initialized; Make_Error always
   --  sets them and only retained entries are ever read.
   type Decoding_Error is record
      Id         : Error_Id := Internal_Decoder_Failure;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind := Structured_Body;
      Origin     : Error_Origin := Decode_Origin;
      Severity   : Severity_Level := Recoverable;
      Location   : Source_Location := No_Location;
      Parameters : Error_Parameters := No_Parameters;
   end record;

   --  Construct a decoding error with sensible defaults.
   --  @param Id The error identifier.
   --  @param Path The exact structured field path.
   --  @param Source The originating source kind.
   --  @param Origin The error origin classification.
   --  @param Severity The severity classification.
   --  @param Location Optional source location.
   --  @param Parameters Structured localization parameters.
   --  @return The constructed error.
   function Make_Error
     (Id         : Error_Id;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind;
      Origin     : Error_Origin := Decode_Origin;
      Severity   : Severity_Level := Recoverable;
      Location   : Source_Location := No_Location;
      Parameters : Error_Parameters := No_Parameters) return Decoding_Error;

   --  The hard capacity of a collection; the effective limit never exceeds it.
   Max_Stored_Errors : constant := 64;

   --  A bounded, deterministically ordered set of errors. Beyond the effective
   --  limit, further errors are counted in Omitted rather than stored, keeping
   --  the first Limit inserted in insertion order.
   type Error_Collection is private;

   --  An empty collection with the given effective limit (clamped to capacity).
   --  @param Limit The maximum number of errors to retain.
   --  @return An empty collection.
   function Empty_Collection
     (Limit : Error_Count := Max_Stored_Errors) return Error_Collection;

   --  Append an error, retaining it when below the limit and otherwise counting
   --  it as omitted. Deterministic: equal inputs yield equal collections.
   --  @param Collection The collection to extend.
   --  @param Error The error to append.
   procedure Append
     (Collection : in out Error_Collection; Error : Decoding_Error);

   --  The number of retained errors.
   --  @param Collection The collection.
   --  @return The retained count.
   function Length (Collection : Error_Collection) return Error_Count;

   --  The number of errors dropped after the limit was reached.
   --  @param Collection The collection.
   --  @return The omitted count.
   function Omitted (Collection : Error_Collection) return Error_Count;

   --  Whether the collection has no retained errors.
   --  @param Collection The collection.
   --  @return True when empty.
   function Is_Empty (Collection : Error_Collection) return Boolean;

   --  A retained error by 1-based position.
   --  @param Collection The collection.
   --  @param Index The 1-based position (1 .. Length).
   --  @return The error at that position.
   function Element
     (Collection : Error_Collection; Index : Positive) return Decoding_Error;

private

   type Error_Array is array (1 .. Max_Stored_Errors) of Decoding_Error;

   type Error_Collection is record
      Limit   : Error_Count := Max_Stored_Errors;
      Count   : Natural := 0;
      Dropped : Error_Count := 0;
      Items   : Error_Array;
   end record;

end Web.Binding.Errors;
