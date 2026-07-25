package body Web.Binding.Record_Binders is

   use Web.Binding.Errors;
   use Web.Binding.Policies;

   function Start
     (Initial : Target;
      Mode    : Web.Binding.Policies.Aggregation_Mode :=
        Web.Binding.Policies.Aggregate_Fields) return Builder is
   begin
      return B : Builder do
         B.Working := Initial;
         B.Errors := Empty_Collection;
         B.Mode := Mode;
         B.Sealed := False;
      end return;
   end Start;

   --  Record one error, sealing the builder in fail-fast mode.
   procedure Record_One (B : in out Builder; Error : Decoding_Error) is
   begin
      Append (B.Errors, Error);
      if B.Mode = Fail_Fast then
         B.Sealed := True;
      end if;
   end Record_One;

   --  Merge a field's error collection into the builder.
   procedure Merge (B : in out Builder; From : Error_Collection) is
   begin
      for I in 1 .. Natural (Length (From)) loop
         Record_One (B, Element (From, I));
         exit when B.Sealed;
      end loop;
   end Merge;

   procedure Bind_Scalar
     (B          : in out Builder;
      Occ        : Web.Binding.Sources.Occurrences;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind;
      Presence   : Web.Binding.Policies.Presence_Policy :=
        Web.Binding.Policies.Required;
      Duplicates : Web.Binding.Policies.Duplicate_Policy :=
        Web.Binding.Policies.Reject;
      On_Empty   : Web.Binding.Policies.Empty_Policy :=
        Web.Binding.Policies.Reject_Empty)
   is
      use Web.Binding.Sources;
      Res : Scalar_Resolution;
   begin
      if B.Sealed then
         return;
      end if;

      Res := Resolve_Scalar (Occ, Duplicates, On_Empty);
      case Res.State is
         when Resolved_Value =>
            declare
               D : constant Field_Results.Result :=
                 Decode (Value (Occ, Res.Index), Path, Source);
            begin
               if Field_Results.Succeeded (D) then
                  Setter (B.Working, Field_Results.Value_Of (D));
               else
                  Merge (B, Field_Results.Errors_Of (D));
               end if;
            end;
         when Resolved_Missing =>
            if Presence = Required then
               Record_One (B, Make_Error (Binding_Missing, Path, Source));
            end if;
         when Resolved_Duplicate =>
            Record_One (B, Make_Error (Binding_Duplicate, Path, Source));
         when Resolved_Empty =>
            Record_One (B, Make_Error (Binding_Empty_Not_Allowed, Path, Source));
         when Resolved_Malformed =>
            Record_One
              (B, Make_Error (Form_Invalid_Percent_Escape, Path, Source));
      end case;
   end Bind_Scalar;

   procedure Bind_Collection
     (B         : in out Builder;
      Occ       : Web.Binding.Sources.Occurrences;
      Base_Path : Web.Binding.Paths.Field_Path;
      Source    : Source_Kind;
      Min_Items : Natural := 0;
      Max_Items : Natural := 1_024)
   is
      use Web.Binding.Sources;
      use Web.Binding.Paths;
      N      : constant Natural := Count (Occ);
      Usable : constant Natural := Natural'Min (N, Max_Items);
   begin
      if B.Sealed then
         return;
      end if;

      if N > Max_Items then
         declare
            Params : Error_Parameters;
         begin
            Params.Has_Maximum := True;
            Params.Maximum := Long_Long_Integer (Max_Items);
            Params.Has_Actual := True;
            Params.Actual := Long_Long_Integer (N);
            Record_One
              (B, Make_Error (Decode_Too_Many_Items, Base_Path, Source,
                              Decode_Origin, Parameters => Params));
         end;
      elsif N < Min_Items then
         declare
            Params : Error_Parameters;
         begin
            Params.Has_Minimum := True;
            Params.Minimum := Long_Long_Integer (Min_Items);
            Params.Has_Actual := True;
            Params.Actual := Long_Long_Integer (N);
            Record_One
              (B, Make_Error (Decode_Invalid_List, Base_Path, Source,
                              Decode_Origin, Parameters => Params));
         end;
      end if;

      for I in 1 .. Usable loop
         exit when B.Sealed;
         declare
            Elem_Path : constant Field_Path :=
              Append_Index (Base_Path, Index_Number (I - 1));
         begin
            if Malformed (Occ, I) then
               Record_One
                 (B, Make_Error (Form_Invalid_Percent_Escape, Elem_Path, Source));
            else
               declare
                  D : constant Element_Results.Result :=
                    Decode (Value (Occ, I), Elem_Path, Source);
               begin
                  if Element_Results.Succeeded (D) then
                     Append (B.Working, Element_Results.Value_Of (D));
                  else
                     Merge (B, Element_Results.Errors_Of (D));
                  end if;
               end;
            end if;
         end;
      end loop;
   end Bind_Collection;

   procedure Bind_Nested
     (B        : in out Builder;
      Present  : Boolean;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Optional : Boolean := False) is
   begin
      if B.Sealed then
         return;
      end if;
      if not Present then
         --  Absent object: None when optional, otherwise the whole object is a
         --  required-but-missing error at its path.
         if not Optional then
            Record_One (B, Make_Error (Binding_Missing, Path, Source));
         end if;
         return;
      end if;

      declare
         R : constant Sub_Results.Result := Sub_Bind;
      begin
         if Sub_Results.Succeeded (R) then
            Setter (B.Working, Sub_Results.Value_Of (R));
         else
            Merge (B, Sub_Results.Errors_Of (R));
         end if;
      end;
   end Bind_Nested;

   procedure Guard_Depth
     (B         : in out Builder;
      Path      : Web.Binding.Paths.Field_Path;
      Source    : Source_Kind;
      Max_Depth : Depth_Count) is
   begin
      if not B.Sealed and then Web.Binding.Paths.Depth (Path) > Max_Depth then
         Record_One (B, Make_Error (Decode_Nesting_Too_Deep, Path, Source));
      end if;
   end Guard_Depth;

   procedure Note_Unknown
     (B      : in out Builder;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind;
      Policy : Web.Binding.Policies.Unknown_Field_Policy) is
   begin
      if B.Sealed then
         return;
      end if;
      case Policy is
         when Ignore =>
            null;
         when Reject =>
            Record_One (B, Make_Error (Binding_Unknown_Field, Path, Source));
         when Collect =>
            --  Collected but never fatal: it does not seal a fail-fast builder.
            Append (B.Errors, Make_Error (Binding_Unknown_Field, Path, Source));
      end case;
   end Note_Unknown;

   procedure Add_Error
     (B : in out Builder; Error : Web.Binding.Errors.Decoding_Error) is
   begin
      if not B.Sealed then
         Record_One (B, Error);
      end if;
   end Add_Error;

   function Has_Errors (B : Builder) return Boolean is
   begin
      return not Is_Empty (B.Errors);
   end Has_Errors;

   function Finish (B : Builder) return Results.Result is
   begin
      if Is_Empty (B.Errors) then
         return Results.Make_Success (B.Working);
      else
         return Results.Make_Failure (B.Errors);
      end if;
   end Finish;

end Web.Binding.Record_Binders;
