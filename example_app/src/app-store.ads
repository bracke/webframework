with Ada.Containers.Indefinite_Vectors;

package App.Store is
   package Todo_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   --  Append a todo title to persistent storage.
   --  @param Title Todo title.
   --  @return No return value.
   procedure Add_Todo (Title : String);

   --  Read persisted todo titles.
   --  @return Todo titles from persistent storage.
   function Todos return Todo_Vectors.Vector;
end App.Store;
