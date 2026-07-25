with Ada.Strings.Bounded;
with Web.Binding.Paths;
with Web.Binding.Results;

--  Enumeration decoder.
--
--  Decodes against an explicit wire mapping, never Ada's enumeration image
--  casing. The mapping is an immutable table built once (Empty_Table + Add),
--  supporting exact or ASCII case-insensitive matching, aliases (several wires
--  for one value) and deprecated aliases (still accepted). An unmatched value is
--  decode.invalid_enum, with the allowed wires surfaced as parameters.
generic
   type Target is (<>);
package Web.Binding.Decoders.Enum_Decoders is

   type Case_Mode is (Case_Sensitive, ASCII_Case_Insensitive);

   Max_Wire     : constant := 64;
   Max_Mappings : constant := 256;

   package Wire_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Wire);

   type Mapping_Table is private;

   --  An empty mapping table with the given case policy.
   --  @param Folding The case-matching policy.
   --  @return An empty table.
   function Empty_Table
     (Folding : Case_Mode := Case_Sensitive) return Mapping_Table;

   --  A table with one more (wire -> value) mapping. Excess mappings past the
   --  capacity are dropped; build tables once at startup.
   --  @param Table The table to extend.
   --  @param Wire The wire spelling.
   --  @param Value The enumeration value it maps to.
   --  @param Deprecated Whether this wire is a deprecated alias.
   --  @return The extended table.
   function Add
     (Table      : Mapping_Table;
      Wire       : String;
      Value      : Target;
      Deprecated : Boolean := False) return Mapping_Table;

   package Results is new Web.Binding.Results (Target);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Text against the mapping table or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @param Table The immutable wire mapping.
   --  @return A success value or a decoding error.
   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind;
      Table  : Mapping_Table) return Result;

private

   type Entry_Record is record
      Wire       : Wire_Strings.Bounded_String;
      Value      : Target := Target'First;
      Deprecated : Boolean := False;
   end record;

   type Entry_Array is array (1 .. Max_Mappings) of Entry_Record;

   type Mapping_Table is record
      Folding : Case_Mode := Case_Sensitive;
      Count   : Natural := 0;
      Entries : Entry_Array;
   end record;

end Web.Binding.Decoders.Enum_Decoders;
