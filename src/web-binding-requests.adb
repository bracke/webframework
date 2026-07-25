package body Web.Binding.Requests is

   use Web.Binding.Errors;

   function Classify (Id : Web.Binding.Errors.Error_Id) return Failure_Class is
   begin
      case Id is
         when Body_Missing_Content_Type | Body_Unsupported_Media_Type
            | Body_Invalid_Content_Type | Body_Codec_Not_Found =>
            return Unsupported_Media_Type;
         when Body_Too_Large | Form_Field_Too_Large | Form_Too_Many_Fields
            | Multipart_Too_Many_Parts | Multipart_Part_Headers_Too_Large
            | Multipart_Field_Too_Large | Multipart_Upload_Too_Large
            | Decode_Value_Too_Long | Decode_Too_Many_Items
            | Json_Depth_Exceeded | Json_Token_Limit_Exceeded =>
            return Payload_Too_Large;
         when Internal_Decoder_Failure | Internal_Binding_Definition_Error =>
            return Internal_Error;
         when others =>
            return Bad_Request;
      end case;
   end Classify;

   --  Severity ordering so the worst class across errors wins.
   function Rank (Class : Failure_Class) return Natural is
     (case Class is
         when Internal_Error          => 4,
         when Unsupported_Media_Type  => 3,
         when Payload_Too_Large       => 2,
         when Not_Found               => 1,
         when Bad_Request             => 0);

   function Classify
     (Errors          : Web.Binding.Errors.Error_Collection;
      Route_Not_Found : Boolean := False) return Failure_Class
   is
      Worst    : Failure_Class := Bad_Request;
      Has_Route : Boolean := False;
   begin
      for I in 1 .. Natural (Length (Errors)) loop
         declare
            E : constant Decoding_Error := Element (Errors, I);
            C : constant Failure_Class := Classify (E.Id);
         begin
            if Rank (C) > Rank (Worst) then
               Worst := C;
            end if;
            if E.Source = Route_Parameter then
               Has_Route := True;
            end if;
         end;
      end loop;

      if Route_Not_Found and then Worst = Bad_Request and then Has_Route then
         return Not_Found;
      end if;
      return Worst;
   end Classify;

   procedure Dispatch
     (Result          : Input_Results.Result;
      Route_Not_Found : Boolean := False) is
   begin
      if Input_Results.Succeeded (Result) then
         On_Success (Input_Results.Value_Of (Result));
      else
         On_Failure
           (Classify (Input_Results.Errors_Of (Result), Route_Not_Found),
            Input_Results.Errors_Of (Result));
      end if;
   end Dispatch;

end Web.Binding.Requests;
