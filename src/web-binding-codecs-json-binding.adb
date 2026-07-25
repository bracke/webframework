with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Binding.Errors;

package body Web.Binding.Codecs.JSON.Binding is

   use Web.Binding.Errors;

   function Current_Shape (R : Reader) return Value_Shape is
   begin
      case Kind (R) is
         when String_Value  => return Shape_String;
         when Number_Value  => return Shape_Number;
         when Boolean_Value => return Shape_Boolean;
         when Null_Value    => return Shape_Null;
         when Start_Object  => return Shape_Object;
         when Start_Array   => return Shape_Array;
         when others        => return Shape_None;
      end case;
   end Current_Shape;

   function Begin_Object (R : Reader) return Boolean is
   begin
      return Kind (R) = Start_Object;
   end Begin_Object;

   function Begin_Array (R : Reader) return Boolean is
   begin
      return Kind (R) = Start_Array;
   end Begin_Array;

   procedure Next_Member
     (R    : in out Reader;
      Key  : out Ada.Strings.Unbounded.Unbounded_String;
      Done : out Boolean) is
   begin
      Key := Null_Unbounded_String;
      Advance (R);
      if Kind (R) = JSON.Key then
         Key := To_Unbounded_String (Text (R));
         Advance (R);  --  position at the member value token
         Done := False;
      else
         --  End_Object (or Error_Token / End_Document on malformed input).
         Done := True;
      end if;
   end Next_Member;

   procedure Next_Element (R : in out Reader; Done : out Boolean) is
   begin
      Advance (R);
      Done := Kind (R) = End_Array
        or else Kind (R) = Error_Token
        or else Kind (R) = End_Document;
   end Next_Element;

   procedure Skip_Value (R : in out Reader) is
      Depth : Integer := 0;
   begin
      loop
         case Kind (R) is
            when Start_Object | Start_Array =>
               Depth := Depth + 1;
            when End_Object | End_Array =>
               Depth := Depth - 1;
            when Error_Token | End_Document =>
               return;
            when others =>
               null;
         end case;
         exit when Depth = 0;
         Advance (R);
      end loop;
   end Skip_Value;

   function Read_Scalar
     (R    : Reader;
      Path : Web.Binding.Paths.Field_Path) return Field_Results.Result
   is
      function Fail
        (Id : Web.Binding.Errors.Error_Id) return Field_Results.Result is
         C : Web.Binding.Errors.Error_Collection :=
           Web.Binding.Errors.Empty_Collection;
      begin
         Web.Binding.Errors.Append
           (C, Make_Error (Id, Path, Structured_Body));
         return Field_Results.Make_Failure (C);
      end Fail;
   begin
      case Current_Shape (R) is
         when Shape_String | Shape_Number =>
            return Decode (Text (R), Path, Structured_Body);
         when Shape_Boolean =>
            return Decode
              ((if Bool_Value (R) then "true" else "false"), Path,
               Structured_Body);
         when Shape_Object | Shape_Array | Shape_Null =>
            return Fail (Json_Unexpected_Kind);
         when Shape_None =>
            return Fail (Json_Malformed);
      end case;
   end Read_Scalar;

   function New_Tracker return Member_Tracker is
      T : Member_Tracker;
   begin
      return T;
   end New_Tracker;

   procedure Note
     (T : in out Member_Tracker; Key : String; Duplicate : out Boolean) is
   begin
      for I in 1 .. T.Count loop
         if To_String (T.Keys (I)) = Key then
            Duplicate := True;
            return;
         end if;
      end loop;
      Duplicate := False;
      if T.Count < Max_Keys then
         T.Count := T.Count + 1;
         T.Keys (T.Count) := To_Unbounded_String (Key);
      end if;
   end Note;

   function Seen (T : Member_Tracker; Key : String) return Boolean is
   begin
      for I in 1 .. T.Count loop
         if To_String (T.Keys (I)) = Key then
            return True;
         end if;
      end loop;
      return False;
   end Seen;

end Web.Binding.Codecs.JSON.Binding;
