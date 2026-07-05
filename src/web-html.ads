with Ada.Strings.Unbounded;

package Web.Html is
   type Trusted_HTML is private;

   --  Escape text for an HTML text node.
   --  @param Text Plain text to escape.
   --  @return Escaped HTML text.
   function Escape_Text (Text : String) return String;

   --  Escape text for an HTML attribute value.
   --  @param Value Plain attribute value to escape.
   --  @return Escaped attribute value.
   function Escape_Attribute (Value : String) return String;

   --  Mark application-rendered HTML as trusted.
   --  @param HTML Rendered HTML supplied by application code.
   --  @return Trusted HTML wrapper.
   function Trusted (HTML : String) return Trusted_HTML;

   --  Convert trusted HTML to a string for transport.
   --  @param HTML Trusted HTML wrapper.
   --  @return Rendered HTML string.
   function To_String (HTML : Trusted_HTML) return String;

   --  Check whether a value is safe as a DOM id.
   --  @param Value Candidate id.
   --  @return True when Value is a valid framework id.
   function Is_Valid_Id (Value : String) return Boolean;

   --  Check whether a value is safe as a CSS class.
   --  @param Value Candidate class.
   --  @return True when Value is a valid framework class.
   function Is_Valid_Class (Value : String) return Boolean;

private
   type Trusted_HTML is record
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;
end Web.Html;
