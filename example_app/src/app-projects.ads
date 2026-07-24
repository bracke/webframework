--  Projects database management for the example application.

with Ada.Containers.Vectors;

package App.Projects is
   --  Project record type
   type Project_Record is record
      Id              : Natural := 0;
      Name            : String (1 .. 100) := [others => ' '];
      Status          : String (1 .. 50) := [others => ' '];
      Project_Type    : String (1 .. 50) := [others => ' '];
      Functions       : String (1 .. 200) := [others => ' '];
      Has_Project_Tools : Boolean := False;
      Has_GNAT        : Boolean := False;
      Has_GitHub      : Boolean := False;
      Has_Alire       : Boolean := False;
   end record;

   --  Vector of project records
   package Project_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Project_Record);

   --  Initialize the projects table
   procedure Initialize;

   --  Add a project to the database
   procedure Add_Project
     (Name        : String;
      Status      : String;
      Project_Type : String;
      Functions   : String;
      Has_Project_Tools : Boolean;
      Has_GNAT        : Boolean;
      Has_GitHub      : Boolean;
      Has_Alire       : Boolean);

   --  Get projects from the database. When Alire_Only, the authorization data
   --  scope is pushed into the query: only Alire-tracked projects are returned,
   --  so out-of-scope rows are never fetched (rather than filtered afterwards).
   --  @param Alire_Only Restrict the query to Alire-tracked projects.
   --  @return The matching project records.
   function Get_Projects
     (Alire_Only : Boolean := False) return Project_Vectors.Vector;

   --  Delete a project from the database
   procedure Delete_Project (Id : Natural);

end App.Projects;
