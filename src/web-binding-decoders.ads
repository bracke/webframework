with Ada.Strings.Bounded;
with Web.Binding.Errors;

--  Scalar decoder framework.
--
--  A decoder turns a syntactic input (text, for phase 1) into a strongly typed
--  Ada value or a structured decoding error, deterministically and without
--  raising on malformed input (invariant BIND-014, and the phase-1 acceptance
--  rule "no malformed-input exception flow"). Each decoder carries static
--  metadata: a stable identifier, an expected-type identifier for diagnostics,
--  the input kinds it accepts, whether it consumes a stream, and its maximum
--  lookahead.
--
--  Concrete decoders live in child packages (Integer_Decoders, Boolean_Decoders,
--  Text_Decoders, Enum_Decoders, UUID_Decoders, ...). Each instantiates its own
--  Web.Binding.Results for its target type and builds results with Single_Error.
--  Combinators (Optional_Decoders, Defaulted_Decoders) wrap a base decoder.
package Web.Binding.Decoders is

   pragma Preelaborate;

   --  The forms of input a decoder may accept.
   type Input_Kind is (Text_Input, Bytes_Input, Null_Input, Absent_Input);

   type Input_Kind_Set is array (Input_Kind) of Boolean;

   --  A decoder that accepts only textual input.
   Text_Only : constant Input_Kind_Set := [Text_Input => True, others => False];

   Max_Identifier : constant := 64;

   package Id_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Identifier);

   --  A stable decoder identifier, e.g. "web.binding.integer".
   subtype Decoder_Id is Id_Strings.Bounded_String;

   --  An expected-type identifier for diagnostics, e.g. "integer" or "uuid".
   subtype Type_Id is Id_Strings.Bounded_String;

   --  Build a bounded identifier from text (truncated to the bound).
   --  @param Text The identifier text.
   --  @return The bounded identifier.
   function To_Identifier (Text : String) return Id_Strings.Bounded_String;

   --  Static description of a decoder.
   type Decoder_Meta is record
      Id              : Decoder_Id;
      Expected_Type   : Type_Id;
      Accepts         : Input_Kind_Set := Text_Only;
      Consumes_Stream : Boolean := False;
      Max_Lookahead   : Byte_Count := 0;
   end record;

   --  A single-error collection, the common failure shape for a scalar decoder.
   --  @param Error The decoding error.
   --  @return A collection holding exactly that error.
   function Single_Error
     (Error : Web.Binding.Errors.Decoding_Error)
      return Web.Binding.Errors.Error_Collection;

   --  Whether Text is well-formed UTF-8: rejects overlong encodings, UTF-16
   --  surrogate code points, continuation bytes out of place, and code points
   --  above U+10FFFF. Total and non-raising.
   --  @param Text The bytes to validate.
   --  @return True when every byte sequence is valid UTF-8.
   function Valid_UTF8 (Text : String) return Boolean;

end Web.Binding.Decoders;
