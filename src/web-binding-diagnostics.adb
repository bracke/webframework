with Web.Binding.Paths;

package body Web.Binding.Diagnostics is

   use Web.Binding.Errors;

   function T (S : String) return Text_Strings.Bounded_String is
     (Text_Strings.To_Bounded_String (S, Drop => Ada.Strings.Right));

   procedure Emit_To (S : access Sink'Class; E : Event) is
   begin
      if S /= null then
         Emit (S.all, E);
      end if;
   end Emit_To;

   function Limit_Category_Of
     (Id : Web.Binding.Errors.Error_Id) return Limit_Category is
   begin
      case Id is
         when Body_Too_Large =>
            return Body_Size;
         when Form_Field_Too_Large | Multipart_Field_Too_Large
            | Decode_Value_Too_Long =>
            return Field_Size;
         when Form_Too_Many_Fields =>
            return Field_Count;
         when Multipart_Too_Many_Parts =>
            return Part_Count;
         when Multipart_Part_Headers_Too_Large =>
            return Header_Size;
         when Multipart_Upload_Too_Large =>
            return Upload_Size;
         when Json_Depth_Exceeded | Decode_Nesting_Too_Deep =>
            return Depth;
         when Json_Token_Limit_Exceeded =>
            return Token_Count;
         when Decode_Too_Many_Items =>
            return Item_Count;
         when others =>
            return No_Limit;
      end case;
   end Limit_Category_Of;

   function Codec_Selected_Event
     (Correlation : String; Route : String; Codec : String) return Event is
   begin
      return (Kind => Codec_Selected, Correlation => T (Correlation),
              Route => T (Route), Codec => T (Codec), others => <>);
   end Codec_Selected_Event;

   function Bind_Succeeded_Event
     (Correlation : String; Route : String) return Event is
   begin
      return (Kind => Bind_Succeeded, Correlation => T (Correlation),
              Route => T (Route), others => <>);
   end Bind_Succeeded_Event;

   function Bind_Failed_Event
     (Errors      : Web.Binding.Errors.Error_Collection;
      Correlation : String;
      Route       : String) return Event
   is
      Result : Event;
   begin
      Result.Kind := Bind_Failed;
      Result.Correlation := T (Correlation);
      Result.Route := T (Route);
      Result.Error_Count := Natural (Length (Errors));
      if not Is_Empty (Errors) then
         declare
            First : constant Decoding_Error := Element (Errors, 1);
         begin
            Result.Has_Error := True;
            Result.Error := First.Id;
            Result.Has_Source := True;
            Result.Source := First.Source;
            Result.Path := Path_Strings.To_Bounded_String
              (Web.Binding.Paths.Render (First.Path), Drop => Ada.Strings.Right);
            Result.Limit := Limit_Category_Of (First.Id);
         end;
      end if;
      return Result;
   end Bind_Failed_Event;

   function Limit_Event
     (Category : Limit_Category; Correlation : String; Route : String)
      return Event is
   begin
      return (Kind => Limit_Exceeded, Correlation => T (Correlation),
              Route => T (Route), Limit => Category, others => <>);
   end Limit_Event;

   function Upload_Aborted_Event
     (Correlation : String; Route : String) return Event is
   begin
      return (Kind => Upload_Aborted, Correlation => T (Correlation),
              Route => T (Route), others => <>);
   end Upload_Aborted_Event;

   function Registry_Failure_Event (Correlation : String) return Event is
   begin
      return (Kind => Registry_Failure, Correlation => T (Correlation),
              others => <>);
   end Registry_Failure_Event;

end Web.Binding.Diagnostics;
