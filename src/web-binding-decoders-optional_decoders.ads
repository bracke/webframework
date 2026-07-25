with Web.Binding.Paths;
with Web.Binding.Results;

--  Optional combinator.
--
--  Wraps a base scalar decoder so an absent value becomes None instead of an
--  error, while a present value is decoded by the base decoder. A present but
--  malformed value stays an error (it is never turned into None). Presence is
--  supplied by the caller (the source layer), keeping this combinator free of
--  any source dependency.
generic
   type Target is private;
   with package Base_Results is new Web.Binding.Results (Target);
   with function Base_Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Base_Results.Result;
package Web.Binding.Decoders.Optional_Decoders is

   --  An optional value: either present with a decoded Target, or absent.
   type Optional_Value (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Target;
         when False =>
            null;
      end case;
   end record;

   package Results is new Web.Binding.Results (Optional_Value);

   subtype Result is Results.Result;

   --  Decode an optional value.
   --  @param Is_Present Whether the source supplied a value.
   --  @param Text The raw input text (ignored when absent).
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return None when absent, the decoded value when present, or the base
   --          decoder's error when present but malformed.
   function Decode
     (Is_Present : Boolean;
      Text       : String;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind) return Result;

end Web.Binding.Decoders.Optional_Decoders;
