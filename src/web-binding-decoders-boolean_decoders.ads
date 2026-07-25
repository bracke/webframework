with Web.Binding.Paths;
with Web.Binding.Results;

--  Boolean decoder.
--
--  The narrow default accepts only "true" and "false". Optional literal sets
--  (1/0, yes/no, on/off) and ASCII case-insensitive matching are opt-in. HTML
--  checkbox semantics (presence means true) are deliberately NOT here; they
--  belong in a Forms adapter or an explicitly configured decoder.
package Web.Binding.Decoders.Boolean_Decoders is

   --  A pair of accepted literals.
   type Literal_Set is (True_False, One_Zero, Yes_No, On_Off);

   type Set_Flags is array (Literal_Set) of Boolean;

   --  The narrow default: true / false only.
   Narrow : constant Set_Flags := [True_False => True, others => False];

   type Config is record
      Accept_Sets      : Set_Flags := Narrow;
      Case_Insensitive : Boolean := False;
   end record;

   Default_Config : constant Config := (others => <>);

   package Results is new Web.Binding.Results (Boolean);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Text into a Boolean or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @param Settings The immutable configuration.
   --  @return A success value or a decoding error.
   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result;

end Web.Binding.Decoders.Boolean_Decoders;
