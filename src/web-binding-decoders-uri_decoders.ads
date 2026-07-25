with Ada.Strings.Bounded;
with Web.Binding.Paths;
with Web.Binding.Results;

--  URI-component decoder (RFC 3986 generic syntax).
--
--  Splits a URI into scheme / authority (host + port) / path / query / fragment
--  and validates the syntax only -- it resolves nothing, contacts nothing, and
--  makes no policy decision about the target. Malformed input is
--  decode.invalid_uri. Useful for fields that are themselves URLs (an OAuth
--  redirect_uri, a webhook callback); authorization of the target is elsewhere.
package Web.Binding.Decoders.URI_Decoders is

   Max_URI : constant := 2_048;

   package URI_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_URI);

   type URI_Parts is record
      Scheme        : URI_Strings.Bounded_String;
      Has_Authority : Boolean := False;
      Host          : URI_Strings.Bounded_String;
      Port          : URI_Strings.Bounded_String;   --  as text, may be empty
      Path          : URI_Strings.Bounded_String;
      Query         : URI_Strings.Bounded_String;
      Fragment      : URI_Strings.Bounded_String;
   end record;

   type Config is record
      Require_Scheme    : Boolean := True;   --  an absolute-form URI
      Require_Authority : Boolean := False;  --  demand "//host"
   end record;

   Default_Config : constant Config := (others => <>);

   package Results is new Web.Binding.Results (URI_Parts);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode a URI into its components or a structured error.
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

end Web.Binding.Decoders.URI_Decoders;
