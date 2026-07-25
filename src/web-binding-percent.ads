--  Percent-decoding, shared by query and URL-encoded form parsing.
--
--  Low-level and total: both hex digits of a %XX escape are validated before a
--  byte is produced, and any malformed escape sets Valid to False rather than
--  raising. Plus_As_Space maps '+' to a space (the form/query convention). The
--  query and body layers wrap this with their own distinct policies.
package Web.Binding.Percent is

   pragma Preelaborate;

   --  Percent-decode Text into Output.
   --  @param Text The encoded input.
   --  @param Plus_As_Space Whether '+' decodes to a space.
   --  @param Output Receives the decoded bytes; must be at least Text'Length.
   --  @param Last The last used index of Output (Output'First - 1 if empty).
   --  @param Valid False if any percent escape was malformed.
   procedure Decode
     (Text          : String;
      Plus_As_Space : Boolean;
      Output        : out String;
      Last          : out Natural;
      Valid         : out Boolean);

   --  Percent-decode Text, returning the decoded string.
   --  @param Text The encoded input.
   --  @param Plus_As_Space Whether '+' decodes to a space.
   --  @param Valid False if any percent escape was malformed.
   --  @return The decoded string.
   function Decode
     (Text          : String;
      Plus_As_Space : Boolean;
      Valid         : out Boolean) return String;

end Web.Binding.Percent;
