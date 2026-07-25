--  Resource limits.
--
--  Every attacker-controlled dimension is bounded. Limits compose in layers:
--  server hard maximum, then route or handler, then binding definition, then
--  field. An inner layer may only reduce an outer one, never raise it
--  (Tighten enforces this by taking the per-field minimum). Fields are strongly
--  typed so a byte bound can never be confused with an item bound.
package Web.Binding.Limits is

   pragma Pure;

   type Binding_Limits is record
      Max_Body_Bytes                 : Byte_Count  := 1_048_576;
      Max_Text_Value_Bytes           : Byte_Count  := 65_536;
      Max_Decoded_String_Length      : Byte_Count  := 65_536;
      Max_Query_Parameters           : Item_Count  := 256;
      Max_Header_Values              : Item_Count  := 256;
      Max_Cookies                    : Item_Count  := 64;
      Max_URL_Encoded_Fields         : Item_Count  := 256;
      Max_Multipart_Parts            : Item_Count  := 64;
      Max_Part_Header_Bytes          : Byte_Count  := 8_192;
      Max_Multipart_Text_Field_Bytes : Byte_Count  := 65_536;
      Max_Single_Upload_Bytes        : Byte_Count  := 10_485_760;
      Max_Total_Upload_Bytes         : Byte_Count  := 52_428_800;
      Max_JSON_Depth                 : Depth_Count := 64;
      Max_JSON_Tokens                : Token_Count := 100_000;
      Max_JSON_Object_Members        : Item_Count  := 1_024;
      Max_Collection_Items           : Item_Count  := 1_024;
      Max_Path_Depth                 : Depth_Count := 32;
      Max_Errors                     : Error_Count := 64;
      Max_Numeric_Literal_Length     : Byte_Count  := 64;
   end record;

   --  Conservative defaults suitable as a starting server hard maximum.
   Default_Limits : constant Binding_Limits := (others => <>);

   --  Combine an outer and an inner limit set field by field, taking the
   --  smaller of each. The result is therefore never looser than either input,
   --  so a definition or field layer can tighten but never widen a server bound.
   --  @param Outer The outer (looser or equal) limits.
   --  @param Inner The inner limits requesting tighter bounds.
   --  @return The per-field minimum of the two.
   function Tighten
     (Outer : Binding_Limits; Inner : Binding_Limits) return Binding_Limits;

   --  Whether every field of Inner is at most the matching field of Outer.
   --  @param Inner The candidate inner limits.
   --  @param Outer The outer limits.
   --  @return True when Inner never exceeds Outer.
   function Is_Within
     (Inner : Binding_Limits; Outer : Binding_Limits) return Boolean;

end Web.Binding.Limits;
