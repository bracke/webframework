package body Web.Binding.Limits is

   function Tighten
     (Outer : Binding_Limits; Inner : Binding_Limits) return Binding_Limits is
   begin
      return
        (Max_Body_Bytes                 =>
           Byte_Count'Min (Outer.Max_Body_Bytes, Inner.Max_Body_Bytes),
         Max_Text_Value_Bytes           =>
           Byte_Count'Min (Outer.Max_Text_Value_Bytes,
                           Inner.Max_Text_Value_Bytes),
         Max_Decoded_String_Length      =>
           Byte_Count'Min (Outer.Max_Decoded_String_Length,
                           Inner.Max_Decoded_String_Length),
         Max_Query_Parameters           =>
           Item_Count'Min (Outer.Max_Query_Parameters,
                           Inner.Max_Query_Parameters),
         Max_Header_Values              =>
           Item_Count'Min (Outer.Max_Header_Values, Inner.Max_Header_Values),
         Max_Cookies                    =>
           Item_Count'Min (Outer.Max_Cookies, Inner.Max_Cookies),
         Max_URL_Encoded_Fields         =>
           Item_Count'Min (Outer.Max_URL_Encoded_Fields,
                           Inner.Max_URL_Encoded_Fields),
         Max_Multipart_Parts            =>
           Item_Count'Min (Outer.Max_Multipart_Parts,
                           Inner.Max_Multipart_Parts),
         Max_Part_Header_Bytes          =>
           Byte_Count'Min (Outer.Max_Part_Header_Bytes,
                           Inner.Max_Part_Header_Bytes),
         Max_Multipart_Text_Field_Bytes =>
           Byte_Count'Min (Outer.Max_Multipart_Text_Field_Bytes,
                           Inner.Max_Multipart_Text_Field_Bytes),
         Max_Single_Upload_Bytes        =>
           Byte_Count'Min (Outer.Max_Single_Upload_Bytes,
                           Inner.Max_Single_Upload_Bytes),
         Max_Total_Upload_Bytes         =>
           Byte_Count'Min (Outer.Max_Total_Upload_Bytes,
                           Inner.Max_Total_Upload_Bytes),
         Max_JSON_Depth                 =>
           Depth_Count'Min (Outer.Max_JSON_Depth, Inner.Max_JSON_Depth),
         Max_JSON_Tokens                =>
           Token_Count'Min (Outer.Max_JSON_Tokens, Inner.Max_JSON_Tokens),
         Max_JSON_Object_Members        =>
           Item_Count'Min (Outer.Max_JSON_Object_Members,
                           Inner.Max_JSON_Object_Members),
         Max_Collection_Items           =>
           Item_Count'Min (Outer.Max_Collection_Items,
                           Inner.Max_Collection_Items),
         Max_Path_Depth                 =>
           Depth_Count'Min (Outer.Max_Path_Depth, Inner.Max_Path_Depth),
         Max_Errors                     =>
           Error_Count'Min (Outer.Max_Errors, Inner.Max_Errors),
         Max_Numeric_Literal_Length     =>
           Byte_Count'Min (Outer.Max_Numeric_Literal_Length,
                           Inner.Max_Numeric_Literal_Length));
   end Tighten;

   function Is_Within
     (Inner : Binding_Limits; Outer : Binding_Limits) return Boolean is
   begin
      return
        Inner.Max_Body_Bytes                 <= Outer.Max_Body_Bytes
        and then Inner.Max_Text_Value_Bytes  <= Outer.Max_Text_Value_Bytes
        and then Inner.Max_Decoded_String_Length
                   <= Outer.Max_Decoded_String_Length
        and then Inner.Max_Query_Parameters  <= Outer.Max_Query_Parameters
        and then Inner.Max_Header_Values     <= Outer.Max_Header_Values
        and then Inner.Max_Cookies           <= Outer.Max_Cookies
        and then Inner.Max_URL_Encoded_Fields
                   <= Outer.Max_URL_Encoded_Fields
        and then Inner.Max_Multipart_Parts   <= Outer.Max_Multipart_Parts
        and then Inner.Max_Part_Header_Bytes <= Outer.Max_Part_Header_Bytes
        and then Inner.Max_Multipart_Text_Field_Bytes
                   <= Outer.Max_Multipart_Text_Field_Bytes
        and then Inner.Max_Single_Upload_Bytes
                   <= Outer.Max_Single_Upload_Bytes
        and then Inner.Max_Total_Upload_Bytes
                   <= Outer.Max_Total_Upload_Bytes
        and then Inner.Max_JSON_Depth        <= Outer.Max_JSON_Depth
        and then Inner.Max_JSON_Tokens       <= Outer.Max_JSON_Tokens
        and then Inner.Max_JSON_Object_Members
                   <= Outer.Max_JSON_Object_Members
        and then Inner.Max_Collection_Items  <= Outer.Max_Collection_Items
        and then Inner.Max_Path_Depth        <= Outer.Max_Path_Depth
        and then Inner.Max_Errors            <= Outer.Max_Errors
        and then Inner.Max_Numeric_Literal_Length
                   <= Outer.Max_Numeric_Literal_Length;
   end Is_Within;

end Web.Binding.Limits;
