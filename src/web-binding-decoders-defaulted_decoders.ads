with Web.Binding.Paths;
with Web.Binding.Results;

--  Default combinator.
--
--  Wraps a base scalar decoder so an absent value is replaced by an explicit
--  default. Crucially, a present but malformed value is NOT replaced by the
--  default: it stays an error (page=abc must not become the default page). The
--  default therefore applies only to absence, never to a decode failure.
generic
   type Target is private;
   with package Base_Results is new Web.Binding.Results (Target);
   with function Base_Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Base_Results.Result;
package Web.Binding.Decoders.Defaulted_Decoders is

   --  Decode a value with a default for absence.
   --  @param Is_Present Whether the source supplied a value.
   --  @param Default The value to use when absent.
   --  @param Text The raw input text (ignored when absent).
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return The default when absent, the decoded value when present, or the
   --          base decoder's error when present but malformed.
   function Decode
     (Is_Present : Boolean;
      Default    : Target;
      Text       : String;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind) return Base_Results.Result;

end Web.Binding.Decoders.Defaulted_Decoders;
