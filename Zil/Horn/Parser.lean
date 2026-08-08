module

public import Zil.Horn.Resolution

@[expose] public section

namespace Zil.Horn.Parser

inductive TokenKind where
  | identifier (value : String)
  | leftParen
  | rightParen
  | comma
  | dot
  | neck
  | eof
  deriving Repr, Inhabited

structure Token where
  kind : TokenKind
  line : Nat
  column : Nat
  deriving Repr, Inhabited

structure ParseError where
  line : Nat
  column : Nat
  message : String
  deriving Repr, Inhabited

def ParseError.render (error : ParseError) : String :=
  s!"{error.line}:{error.column}: {error.message}"

instance : ToString ParseError := ⟨ParseError.render⟩

def identifierChar (character : Char) : Bool :=
  character.isAlphanum || character == '_'

def takeIdentifier : List Char → List Char × List Char
  | [] => ([], [])
  | character :: rest =>
      if identifierChar character then
        let (name, remaining) := takeIdentifier rest
        (character :: name, remaining)
      else ([], character :: rest)

def skipComment : List Char → List Char
  | [] => []
  | '\n' :: rest => '\n' :: rest
  | _ :: rest => skipComment rest

partial def tokenizeLoop
    (characters : List Char) (line column : Nat) (tokens : List Token) :
    Except ParseError (List Token) :=
  match characters with
  | [] => .ok (tokens.reverse ++ [{ kind := .eof, line, column }])
  | character :: rest =>
      if character == '\n' then tokenizeLoop rest (line + 1) 1 tokens
      else if character.isWhitespace then tokenizeLoop rest line (column + 1) tokens
      else if character == '%' then tokenizeLoop (skipComment rest) line (column + 1) tokens
      else if character == '(' then
        tokenizeLoop rest line (column + 1) ({ kind := .leftParen, line, column } :: tokens)
      else if character == ')' then
        tokenizeLoop rest line (column + 1) ({ kind := .rightParen, line, column } :: tokens)
      else if character == ',' then
        tokenizeLoop rest line (column + 1) ({ kind := .comma, line, column } :: tokens)
      else if character == '.' then
        tokenizeLoop rest line (column + 1) ({ kind := .dot, line, column } :: tokens)
      else if character == ':' then
        match rest with
        | '-' :: tail => tokenizeLoop tail line (column + 2) ({ kind := .neck, line, column } :: tokens)
        | _ => .error { line, column, message := "expected '-' after ':'" }
      else if identifierChar character then
        let (suffix, remaining) := takeIdentifier rest
        let name := String.ofList (character :: suffix)
        tokenizeLoop remaining line (column + name.length)
          ({ kind := .identifier name, line, column } :: tokens)
      else
        .error { line, column, message := s!"unexpected character '{character}'" }

/-- Tokenize the pure Prolog notation used by HORC `.hn` files. The accepted
surface is deliberately definite-Horn only: identifiers, constructor terms,
facts, `:-`, conjunction, and `%` line comments. -/
def tokenize (text : String) : Except ParseError (List Token) :=
  tokenizeLoop text.toList 1 1 []

structure ParserState where
  tokens : List Token
  anonymous : Nat := 0
  deriving Inhabited

abbrev ParserM := StateT ParserState (Except ParseError)

def current : ParserM Token := do
  match (← get).tokens with
  | token :: _ => pure token
  | [] => pure { kind := .eof, line := 1, column := 1 }

def advance : ParserM Token := do
  let state ← get
  match state.tokens with
  | [] => pure { kind := .eof, line := 1, column := 1 }
  | token :: rest =>
      set { state with tokens := rest }
      pure token

def fail (token : Token) (message : String) : ParserM α :=
  throw { line := token.line, column := token.column, message }

def consumeLeftParen : ParserM Unit := do
  let token ← advance
  match token.kind with
  | .leftParen => pure ()
  | _ => fail token "expected '('"

def consumeRightParen : ParserM Unit := do
  let token ← advance
  match token.kind with
  | .rightParen => pure ()
  | _ => fail token "expected ')'"

def consumeDot : ParserM Unit := do
  let token ← advance
  match token.kind with
  | .dot => pure ()
  | _ => fail token "expected '.' after Horn clause"

def isVariableName (name : String) : Bool :=
  match name.toList.head? with
  | some character => character.isUpper || character == '_'
  | none => false

def parsedVariable (name : String) : ParserM Zil.Horn.Term := do
  if name == "_" then
    let state ← get
    set { state with anonymous := state.anonymous + 1 }
    pure (.variable s!"$anonymous.{state.anonymous}")
  else pure (.variable name)

mutual
  partial def parseTerm : ParserM Zil.Horn.Term := do
    let token ← advance
    match token.kind with
    | .identifier name =>
        if isVariableName name then parsedVariable name
        else
          match (← current).kind with
          | .leftParen =>
              consumeLeftParen
              pure (.app name (← parseArguments))
          | _ => pure (.constant name)
    | _ => fail token "expected a variable or constructor term"

  partial def parseArguments : ParserM (List Zil.Horn.Term) := do
    match (← current).kind with
    | .rightParen => consumeRightParen; pure []
    | _ =>
        let first ← parseTerm
        parseArgumentTail [first]

  partial def parseArgumentTail (reversed : List Zil.Horn.Term) : ParserM (List Zil.Horn.Term) := do
    let token ← current
    match token.kind with
    | .comma =>
        let _ ← advance
        parseArgumentTail ((← parseTerm) :: reversed)
    | .rightParen =>
        consumeRightParen
        pure reversed.reverse
    | _ => fail token "expected ',' or ')' in argument list"
end

partial def parseAtom : ParserM Zil.Horn.Atom := do
  match ← parseTerm with
  | .app predicate arguments => pure { predicate, arguments }
  | .variable _ => fail (← current) "a predicate position cannot be a variable"

partial def parseBodyTail (reversed : List Zil.Horn.Atom) : ParserM (List Zil.Horn.Atom) := do
  let token ← current
  match token.kind with
  | .comma =>
      let _ ← advance
      parseBodyTail ((← parseAtom) :: reversed)
  | .dot => pure reversed.reverse
  | .eof => pure reversed.reverse
  | _ => fail token "expected ',' or '.' after Horn goal"

partial def parseClause : ParserM Zil.Horn.Clause := do
  let head ← parseAtom
  let token ← current
  match token.kind with
  | .dot => consumeDot; pure { head }
  | .neck =>
      let _ ← advance
      let first ← parseAtom
      let body ← parseBodyTail [first]
      consumeDot
      pure { head, body }
  | _ => fail token "expected '.' or ':-' after clause head"

partial def parseClauses (reversed : List Zil.Horn.Clause) : ParserM Zil.Horn.Program := do
  match (← current).kind with
  | .eof => pure reversed.reverse
  | _ => parseClauses ((← parseClause) :: reversed)

def runParser (tokens : List Token) (parser : ParserM α) : Except ParseError α := do
  let (value, _) ← parser.run { tokens }
  pure value

def parseText (text : String) : Except ParseError Zil.Horn.Program := do
  let tokens ← tokenize text
  let program ← runParser tokens (parseClauses [])
  if program.isEmpty then .error { line := 1, column := 1, message := "Horn program is empty" }
  else pure program

def parseGoalsText (text : String) : Except ParseError (List Zil.Horn.Atom) := do
  let tokens ← tokenize text
  runParser tokens do
    let first ← parseAtom
    let goals ← parseBodyTail [first]
    match (← current).kind with
    | .dot => let _ ← advance; pure goals
    | .eof => pure goals
    | _ => fail (← current) "unexpected input after Horn query"

def parseFile (path : String) : IO (Except ParseError Zil.Horn.Program) := do
  parseText (← IO.FS.readFile path) |> pure

end Zil.Horn.Parser
