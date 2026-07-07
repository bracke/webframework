with Ada.Containers.Indefinite_Vectors;

--  Persistent todo storage adapter.
--  Keeps persistence concerns isolated from handlers and page rendering.
package App.Store is
   Storage_Error : exception;

   --  Ordered storage for todo titles exposed as an in-memory vector.
   package Todo_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   --  Append a todo title to persistent storage.
   --  @param Title Todo title.
   --  @return No return value.
   procedure Add_Todo (Title : String);

   --  Return stored todo titles in insertion/ID order.
   --  Read persisted todo titles.
   --  @return Todo titles from persistent storage.
   function Todos return Todo_Vectors.Vector;
end App.Store;
