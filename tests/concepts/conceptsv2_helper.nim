type
  ShadowConcept* = concept
    proc iGetShadowed(s: Self)
  DummyFitsObj* = object
  
proc iGetShadowed*(s: DummyFitsObj)=
  discard

