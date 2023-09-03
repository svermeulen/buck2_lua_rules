-- Note that this needs to manually be kept in sync with the
-- dependencies in BUCK
return {
   source_dir = ".",
   include_dir = {
     ".",
     "../lib1",
   },
}
