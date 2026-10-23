/*
 * @zil target=t:one
 * t:one#kind@star.
 * t:one#kind@again.
 * @endzil
 */
/* @zil target=t:two
/* t:two#kind@opener. */
t:two#kind@closer. */
@endzil
// @zil target=t:three
// t:three#kind@slashes.
/// t:three#kind@tripleslash.
;; t:three#kind@semicolons.
### t:three#kind@hashes.
   t:three#kind@indented.   
@endzil
