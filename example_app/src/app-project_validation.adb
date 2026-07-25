with Validation.Identifiers;
with Validation.Contexts;
with Validation.Validators;
with Validation.Standard.Text;
with Validation.Projections;

package body App.Project_Validation is

   package Ids renames Validation.Identifiers;
   package Res renames Validation.Results;
   package Proj renames Validation.Projections;

   function Get_Name (Input : Project_Input) return String is
     (To_String (Input.Name));
   function Get_Status (Input : Project_Input) return String is
     (To_String (Input.Status));
   function Get_Type (Input : Project_Input) return String is
     (To_String (Input.Project_Type));
   function Get_Functions (Input : Project_Input) return String is
     (To_String (Input.Functions));

   package PV is new Validation.Validators (Project_Input);
   package Name_Text is new Validation.Standard.Text (Project_Input, PV, Get_Name);
   package Status_Text is new Validation.Standard.Text (Project_Input, PV, Get_Status);
   package Type_Text is new Validation.Standard.Text (Project_Input, PV, Get_Type);
   package Funcs_Text is new Validation.Standard.Text (Project_Input, PV, Get_Functions);

   F_Name   : constant Ids.Field_Id := Ids.Field_Ids.Make ("name");
   F_Status : constant Ids.Field_Id := Ids.Field_Ids.Make ("status");
   F_Type   : constant Ids.Field_Id := Ids.Field_Ids.Make ("project_type");
   F_Funcs  : constant Ids.Field_Id := Ids.Field_Ids.Make ("functions");

   --  Field-size limits mirror App.Projects.Project_Record so a valid input
   --  always fits the fixed-width columns.
   function Build return PV.Validator is
      B : PV.Builder := PV.Start (Ids.Validator_Ids.Make ("project.create"));
   begin
      PV.Add (B, Name_Text.Non_Empty (F_Name, Ids.Rule_Ids.Make ("name/required")));
      PV.Add (B, Name_Text.Max_Length (F_Name, 100, Ids.Rule_Ids.Make ("name/maxlen")));
      PV.Add (B, Status_Text.Non_Empty (F_Status, Ids.Rule_Ids.Make ("status/required")));
      PV.Add (B, Status_Text.Max_Length (F_Status, 50, Ids.Rule_Ids.Make ("status/maxlen")));
      PV.Add (B, Type_Text.Max_Length (F_Type, 50, Ids.Rule_Ids.Make ("type/maxlen")));
      PV.Add (B, Funcs_Text.Max_Length (F_Funcs, 200, Ids.Rule_Ids.Make ("functions/maxlen")));
      return PV.Get_Validator (PV.Finalize (B));
   end Build;

   The_Validator : constant PV.Validator := Build;
   Empty_Context : constant Validation.Contexts.Context :=
     Validation.Contexts.Freeze (Validation.Contexts.New_Builder);

   function Validate (Input : Project_Input) return Validation.Results.Result is
     (PV.Validate (Input, The_Validator, Empty_Context));

   function Error_JSON (Result : Validation.Results.Result) return String is
      Body_Text : Unbounded_String :=
        To_Unbounded_String ("{""status"":""error"",""issues"":[");
   begin
      for Index in 1 .. Res.Issue_Count (Result) loop
         declare
            Compact : constant Proj.Compact_Issue :=
              Proj.Compact (Res.Issue_At (Result, Index));
         begin
            if Index > 1 then
               Append (Body_Text, ",");
            end if;
            Append (Body_Text,
                    "{""path"":""" & To_String (Compact.Primary_Path)
                    & """,""message"":""" & To_String (Compact.Message_Id)
                    & """}");
         end;
      end loop;
      Append (Body_Text, "]}");
      return To_String (Body_Text);
   end Error_JSON;

end App.Project_Validation;
