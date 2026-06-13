package Textrender.Atlases is

   subtype Alpha is Textrender.Alpha;

   subtype Alpha_Buffer is Textrender.Alpha_Buffer;

   type Atlas is private;

   procedure Init
     (A      : in out Atlas;
      Width  : Positive;
      Height : Positive);

   procedure Reset (A : in out Atlas);

   function Width  (A : Atlas) return Positive;
   function Height (A : Atlas) return Positive;

   function Pixels
     (A : Atlas) return access constant Alpha_Buffer;

   function Allocate_Rect
     (A : in out Atlas;
      W : Positive;
      H : Positive;
      X : out Natural;
      Y : out Natural) return Boolean;

   procedure Clear (A : in out Atlas);

   procedure Write_Pixel
     (A : in out Atlas;
      X : Natural;
      Y : Natural;
      Value : Alpha);

   procedure Blend_Max
     (A : in out Atlas;
      X : Natural;
      Y : Natural;
      Value : Alpha);

private

   type Alpha_Buffer_Access is access all Alpha_Buffer;

   type Atlas is record
      Width_V  : Positive := 1;
      Height_V : Positive := 1;

      Data : Alpha_Buffer_Access := null;

      Next_X     : Natural := 0;
      Next_Y     : Natural := 0;
      Row_Height : Natural := 0;
   end record;

end Textrender.Atlases;