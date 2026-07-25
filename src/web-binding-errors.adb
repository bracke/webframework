with Ada.Characters.Handling;

package body Web.Binding.Errors is

   function Id_Key (Id : Error_Id) return String is
      Raw     : constant String := Error_Id'Image (Id);
      Result  : String (Raw'Range);
      Dotted  : Boolean := False;
   begin
      --  Lowercase the literal and turn the first underscore into the namespace
      --  dot: BINDING_MISSING -> binding.missing. Deterministic and total.
      for I in Raw'Range loop
         if Raw (I) = '_' and then not Dotted then
            Result (I) := '.';
            Dotted := True;
         else
            Result (I) := Ada.Characters.Handling.To_Lower (Raw (I));
         end if;
      end loop;
      return Result;
   end Id_Key;

   function Text_Param (Text : String) return Param_Text is
   begin
      return Param_Strings.To_Bounded_String (Text, Drop => Ada.Strings.Right);
   end Text_Param;

   function Make_Error
     (Id         : Error_Id;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind;
      Origin     : Error_Origin := Decode_Origin;
      Severity   : Severity_Level := Recoverable;
      Location   : Source_Location := No_Location;
      Parameters : Error_Parameters := No_Parameters) return Decoding_Error is
   begin
      return
        (Id         => Id,
         Path       => Path,
         Source     => Source,
         Origin     => Origin,
         Severity   => Severity,
         Location   => Location,
         Parameters => Parameters);
   end Make_Error;

   function Empty_Collection
     (Limit : Error_Count := Max_Stored_Errors) return Error_Collection
   is
      Result : Error_Collection;
   begin
      Result.Limit := Error_Count'Min (Limit, Max_Stored_Errors);
      return Result;
   end Empty_Collection;

   procedure Append
     (Collection : in out Error_Collection; Error : Decoding_Error) is
   begin
      if Error_Count (Collection.Count) < Collection.Limit then
         Collection.Count := Collection.Count + 1;
         Collection.Items (Collection.Count) := Error;
      else
         Collection.Dropped := Collection.Dropped + 1;
      end if;
   end Append;

   function Length (Collection : Error_Collection) return Error_Count is
   begin
      return Error_Count (Collection.Count);
   end Length;

   function Omitted (Collection : Error_Collection) return Error_Count is
   begin
      return Collection.Dropped;
   end Omitted;

   function Is_Empty (Collection : Error_Collection) return Boolean is
   begin
      return Collection.Count = 0;
   end Is_Empty;

   function Element
     (Collection : Error_Collection; Index : Positive) return Decoding_Error is
   begin
      return Collection.Items (Index);
   end Element;

end Web.Binding.Errors;
