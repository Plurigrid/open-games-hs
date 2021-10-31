-- A parser for Lambda Calculus
module Preprocessor.Lambda

import Preprocessor.AbstractSyntax
import Data.String.Parser
import Data.String.Parser.Expression
import public Data.List1

public export
Name : Type
Name = String

public export
data Literal
  = LInt Integer
  | LBool Bool
  | LString String

export
Show Literal where
  show (LInt x) = show x
  show (LBool x) = show x
  show (LString x) = x
  
public export
data Pattern
  = PVar Name                -- Just a variable
  | PTuple (List Pattern)    -- Tuple pattern
  | PCon Name (List Pattern) -- constructor pattern
  | PList (List Pattern)     -- List pattern
  | PLit Literal             -- Match a literal exactly

mutual
  public export
  data Lambda
    = Var Name
    | App Lambda Lambda
    | Lam Pattern Lambda
    | Lit Literal
    | LList (List Lambda)
    | Do (List (Maybe Name, Lambda))
    | Tuple Lambda Lambda (List Lambda)
    | Range LRange
    | IfThenElse Lambda Lambda Lambda
    | Ifix String Lambda Lambda
    | PFix String Lambda
    | LLet Pattern Lambda Lambda
    | Unbound Name

  export
  Show Lambda where
    show lb = ?imp
  
  public export
  data LRange =
                LFromR Lambda
              | LFromThenR Lambda Lambda
              | LFromToR Lambda Lambda
              | LFromThenToR Lambda Lambda Lambda

  Show LRange where
    show (LFromR x) = "[ \{show x} ..]"
    show (LFromThenR x y) = "[ \{show x}, \{show y} .. ]"
    show (LFromToR x y) = "[ \{show x} .. \{show y}]"
    show (LFromThenToR x y z) = "[ \{show x},{show y} .. \{show z}]"



languageKeywords : List String
languageKeywords = ["if", "then", "else", "data", "import", "do", "let", "in"
                   , "inputs", "outputs"
                   , "feedback", "returns"
                   , "operation"
                   ]

-- modifiedHaskell : LanguageDef st
-- modifiedHaskell = emptyDef
--                 { Tok.commentStart   = "{-"
--                 , Tok.commentEnd     = "-}"
--                 , Tok.commentLine    = "//"
--                 , Tok.nestedComments = True
--                 , Tok.identStart     = letter
--                 , Tok.identLetter    = alphaNum <|> oneOf "_'"
--                 , Tok.opStart        = Tok.opLetter modifiedHaskell
--                 , Tok.opLetter       = oneOf ":!#$%&*+./<=>?@\\^-~"
--                 , Tok.reservedOpNames= ["::","..","=","\\","|","<-","->","@","~","=>", "$", "-<", ";", "|", "<<=", "||", "=>>", "_"]
--                 , Tok.reservedNames  = languageKeywords
--                 , Tok.caseSensitive  = True
--                 }
many1 : Parser a -> Parser (List1 a)
many1 p = [| p ::: many p |]

try : Functor m => ParseT m a -> ParseT m a
try (P runParser) =
    P $ \st => reverseResult st <$> runParser st
    where 
        reverseResult : State -> Result a -> Result a
        reverseResult s (Fail a b ) = ?whuit 
        reverseResult s (OK a b)   = ?igno

mutual
  sepEndBy1 : Parser a -> Parser sep -> Parser (List a)
  sepEndBy1 p sep     = do{ x <- p
                          ; do{ ignore sep
                              ; xs <- sepEndBy p sep
                              ; pure (x::xs)
                              } <|> pure [x]
                          }
  
  
  sepEndBy :  Parser a -> Parser sep -> Parser (List a)
  sepEndBy p sep = sepEndBy1 p sep <|> pure []
  
colon : Parser ()
colon = token ":"

semi : Parser ()
semi = token ";"

choice : List (Parser a) -> Parser a
choice = foldr (\x, y => x <|> y) empty 

oneOf : String -> Parser Char
oneOf xs = foldr (\x, y => x <|> y) (fail "none of \{show xs}") (map (char) (unpack xs))

reserved : String -> Parser ()
reserved name = lexeme (string name *> requireFailure alphaNum)

reservedOp : String -> Parser ()
reservedOp op = lexeme (string op *> requireFailure (oneOf ":!#$%&*+./<=>?@\\^-~"))

identifier : Parser String
identifier = pack <$> some (alphaNum <|> oneOf "_'")

surround : Parser a -> Parser b -> Parser c -> Parser c
surround l r m = l *> m <* r

brackets : Parser a -> Parser a
brackets = surround (char '[') (char ']')

braces : Parser a -> Parser a
braces = surround (char '{') (char '}')

comma : Parser ()
comma = token ","

contents : Parser a -> Parser a
contents p = spaces *> p <* eos

mkInfix : String -> Parser (Lambda -> Lambda -> Lambda)
mkInfix op = reservedOp op >> pure (Ifix op)

-- stirng literals do not escape for now
stringLiteral : Parser String
stringLiteral   = lexeme (
                  do{ str <- surround (char '"')
                                      (char '"' <?> "end of string")
                                      (many stringChar)
                    ; pure (pack (foldr (maybe id (::)) [] str))
                    }
                  <?> "literal string")
    where
      stringLetter : Parser Char
      stringLetter = satisfy (\c => (c /= '"') && (c /= '\\') && (c > '\026'))

      stringChar : Parser (Maybe Char)
      stringChar = (Just <$> stringLetter)
                      -- <|> stringEscape
                      <?> "string character"

operators : OperatorTable (Lambda)
operators = [ [Infix (mkInfix "$") AssocRight]
            , [Infix (mkInfix ">>=") AssocLeft]
            , [Infix (mkInfix "*>") AssocLeft
              ,Infix (mkInfix "<*") AssocLeft
              ,Infix (mkInfix "<*>") AssocLeft
              ,Infix (mkInfix ">") AssocLeft
              ,Infix (mkInfix "<") AssocLeft
              ,Infix (mkInfix "<=") AssocNone
              ,Infix (mkInfix ">=") AssocNone
              ]
            , [Prefix (reservedOp "-" *> pure (PFix "-"))]
            , [Infix (mkInfix "++") AssocRight]
            , [Infix (mkInfix "+") AssocLeft
              ,Infix (mkInfix "-") AssocLeft
              ,Infix (mkInfix "<>") AssocRight
              ]
            , [Infix (mkInfix "*") AssocLeft
              ,Infix (mkInfix "/") AssocLeft]
            ]

-- infix parser needs a parser to parse expressiosn around the operators
infixParser : Parser Lambda -> Parser Lambda
infixParser lambda = buildExpressionParser Lambda operators lambda


-- ^ Parse a variable as a Lambda term
variable : Parser Lambda
variable = Var <$> identifier 

-- ^ Parse an Integer as a Lambda term
number : Parser Lambda
number = pure $ Lit (LInt (cast !natural))

-- ^ Parse a string literal as a Lambda term
strLit : Parser Lambda
strLit = Lit . LString <$> stringLiteral 

-- ^ Parse two things in sequence and bundle them in a pair
pair : Parser a -> Parser b -> Parser (a, b)
pair p1 p2 = do r1 <- p1; r2 <- p2; pure (r1, r2)

parseLit : Parser Literal
parseLit = LString <$> stringLiteral 
       <|> LInt . cast <$> natural

parseUnbound : Parser Lambda
parseUnbound = reservedOp "_" *> pure (Unbound "")

isConstructor : String -> Bool
isConstructor str = case fastUnpack str of
                         (x :: xs) => isUpper x
                         _ => False

parsePattern : Parser Pattern
parsePattern =
  (do p <- identifier ;
      if isConstructor p then PCon p <$> many parsePattern
                          else pure $ PVar p)
  <|> PTuple <$> parens (commaSep parsePattern)
  <|> PList <$> brackets (commaSep parsePattern)
  <|> PLit <$> parseLit

mutual 
  doNotation : Parser Lambda
  doNotation =
    Do <$> (reserved "do"
        *> braces (statement `sepEndBy` reservedOp ";"))
    where
      statement : Parser (Maybe String, Lambda)
      statement = try ((Just <$> identifier <* reservedOp "<-") `pair` expr)
              <|> ((the (Maybe String) Nothing ,) <$> expr)

  parseLet : Parser Lambda
  parseLet = do
    reserved "let"
    varName <- parsePattern
    reservedOp "="
    value <- expr
    reserved "in"
    body <- expr
    pure (LLet varName value body)

  parseTuple : Parser Lambda
  parseTuple = do
    f <- expr
    ignore comma
    s <- expr
    rest <- many (comma *> expr)
    pure (Tuple f s rest)

  lambda : Parser Lambda
  lambda = do
    reservedOp "\\"
    args <- some parsePattern
    reservedOp "->"
    body <- expr
    pure $ foldr Lam body args

  ifExp : Parser Lambda
  ifExp = do
    ignore $ reserved "if"
    prd <- term
    ignore $ reserved "then"
    thn <- term
    ignore $ reserved "else"
    els <- term
    pure $ IfThenElse prd thn els

  ||| Parse a bracketed expression
  ||| Those are a bit complicated because they can be either a list
  ||| Or a range with begining and end
  ||| Or an infinite list
  ||| Or a range with begining and end and a step size
  ||| Or an infinite list with a step size
  bracketed : Parser Lambda
  bracketed =
    (do { e1 <- expr -- first check we have at least one element
        ; do { e2 <- comma *> expr -- then expect a comma
             -- after the comma we either have more elements or …
             ; (comma *> (LList . (\x => e1 :: e2 :: x) <$> commaSep expr) <|>
             -- … or we have a range starting with `..`
               (Range <$> (reservedOp ".." *>
                                (LFromThenToR e1 e2 <$> expr <|>
                                 pure (LFromR e1))))) <|>
               pure (LList [e1, e2])
             } <|> -- if there is no comma, check if there is `..` to parse a range
               reservedOp ".." *> (Range <$> (LFromToR e1 <$> expr <|> pure (LFromR e1)))
        })
    <|> pure (LList [])

  term : Parser Lambda
  term =  parens (try parseTuple <|> expr)
      <|> ifExp
      <|> lambda
      <|> variable
      <|> number
      <|> strLit
      <|> brackets bracketed
      <|> doNotation
      <|> parseLet
      <|> parseUnbound
  appl : Parser Lambda
  appl = do
    es <- many1 term
    pure (foldl1 App es)

  expr : Parser Lambda
  expr = infixParser appl

parseTwoLines : String -> String -> Parser p -> Parser e -> Parser (List p, List e)
parseTwoLines kw1 kw2 parseP parseE =
    pair (reserved kw1 *> colon *> commaSep parseP <* semi )
         (option [] (reserved kw2 *> colon *> commaSep parseE <* semi ))
 <|> (([], ) <$> (reserved kw2 *> colon *> commaSep parseE <* semi))

parseInput : Parser p -> Parser e -> Parser (List p, List e)
parseInput = parseTwoLines "inputs" "feedback"

parseOutput : Parser p -> Parser e -> Parser (List p, List e)
parseOutput = parseTwoLines "outputs" "returns"

parseDelimiter : Parser (List String)
parseDelimiter = colon *> some (string "-") <* colon

parseVerboseLine : Parser p -> Parser e -> Parser (Line p e)
parseVerboseLine parseP parseE = do
  (covIn, conOut) <- option ([], []) (parseInput parseE parseP)
  program <- reserved "operation" *> colon *> parseE <* semi
  (covOut,conIn) <- option ([], []) (parseOutput parseP parseE)
  pure $ MkLine covIn conOut program covOut conIn 

export
parseVerboseSyntax : Parser p -> Parser e -> Parser (Block p e)
parseVerboseSyntax parseP parseE =
  do (covIn, conOut) <- try (parseInput parseP parseE <* parseDelimiter) <|> pure ([], [])
     lines <- many (parseVerboseLine parseP parseE)
     (covOut,conIn) <- option ([], []) (parseDelimiter *> parseOutput parseE parseP)
     pure $ MkBlock covIn conOut lines covOut conIn

     {-
     -}
