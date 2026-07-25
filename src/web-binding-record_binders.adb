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
