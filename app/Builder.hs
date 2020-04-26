{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}

module Builder where

import Control.Applicative ((<$>))

import Data.Maybe
import Data.Map ((!))
import qualified Data.Map as Map
import Data.Word (Word32)

import LLVM.AST hiding (function, alignment)
import LLVM.AST.AddrSpace
import LLVM.AST.Type as AST
import qualified LLVM.AST as A
import qualified LLVM.AST.Float as F
import qualified LLVM.AST.Constant as C

import LLVM.IRBuilder.Module
import LLVM.IRBuilder.Monad
import LLVM.IRBuilder.Instruction hiding (load, store)
import LLVM.IRBuilder.Constant
import qualified LLVM.IRBuilder.Instruction as I

import StringUtils
import Syntax

addrSpace :: AddrSpace
addrSpace = AddrSpace 0

iSize :: Word32
iSize = 32

alignment :: Word32
alignment = 4

integerConstant i = ConstantOperand (C.Int {C.integerBits = iSize, C.integerValue = i})

integerPointer :: AST.Type
integerPointer = AST.PointerType i32 addrSpace

allocate :: MonadIRBuilder m => AST.Type -> m Operand
allocate type_ = alloca type_ Nothing alignment

allocateInt :: MonadIRBuilder m => m Operand
allocateInt = allocate i32

load :: MonadIRBuilder m => Operand -> m Operand
load pointer = I.load pointer alignment

store :: MonadIRBuilder m => Operand -> Operand -> m ()
store pointer value = I.store pointer alignment value

saveInt :: MonadIRBuilder m => Integer -> m Operand
saveInt value = do
  pointer <- allocateInt
  store pointer (int32 value)
  return pointer

refName :: String -> A.Name
refName name = Name (toShort' $  name ++ "_0")

reference :: AST.Type -> String -> Operand
reference type_ name = LocalReference type_ (refName name)

referenceInt :: String -> Operand
referenceInt name = reference i32 name

referenceIntPointer :: String -> Operand
referenceIntPointer name = reference integerPointer name

typeMap = Map.fromList [(IntType, i32)]

argDef (Def defType name) = (typeMap ! defType, ParameterName $ toShort' name)

extractDefs :: MonadIRBuilder m => [Expr] -> m ()
extractDefs (expr:exprs) = do
  extractDef expr
  extractDefs exprs
extractDefs [] = pure ()

extractDef :: MonadIRBuilder m => Expr -> m ()
extractDef (BinaryOp "=" maybeDef _) = case maybeDef of
  Def defType defName -> do
    allocateInt `named` toShort' defName
    pure ()
  _ -> pure ()
extractDef _ = pure ()

emitAll :: MonadIRBuilder m => [Expr] -> m ()
emitAll (expr:exprs) = do
  emit expr
  emitAll exprs
emitAll [] = pure ()

emit :: MonadIRBuilder m => Expr -> m ()
emitInner :: MonadIRBuilder m => Expr -> m Operand

-- Binary Op, UnaryOp
emitInner _ = error "Impossible inner expression (error messages are WIP)"

emit (BinaryOp "=" dest object) = 
  do
    value <- case object of
      Int i -> pure (int32 i)
      Var v -> load (referenceIntPointer v)
      _ -> emitInner object 
    store (referenceIntPointer name) value
  where
    name = case dest of 
      Def _ n -> n
      Var n -> n

emit _ = pure ()

funcBodyBuilder :: MonadIRBuilder m => [Expr] -> ([Operand] -> m ())
funcBodyBuilder bodyTokens = func
  where
    func argOperands = do
      -- Steps of codegen
      extractDefs bodyTokens
      emitAll bodyTokens

functionAST (Syntax.Function retType name args body) = 
  function (Name $ toShort' name) arguments (typeMap ! retType) funcBody
  where arguments = map argDef args
        funcBody = funcBodyBuilder body

buildAST :: [Expr] -> Module
buildAST [func] = buildModule "program" $ mdo functionAST func
