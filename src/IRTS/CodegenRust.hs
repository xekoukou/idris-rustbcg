module IRTS.CodegenRust(codegenRust) where

import IRTS.CodegenCommon
import IRTS.Lang
import Idris.Core.TT
import Data.Char (ord)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Debug.Trace


-- This is the main function

codegenRust :: CodeGenerator
codegenRust ci = do putStrLn $ codegenRust' $ Map.fromList (liftDecls ci)

codegenRust' :: Map Name LDecl -> String
codegenRust' m = let nm = (sMN 0 "runMain") 
                 in let Just decl = Map.lookup nm m 
		    in let (LFun _ _ _ fn) = decl
                       in  concat (map genLDecl $ Map.toList $ eraseVarFun $ Map.fromList $ (nm,decl) : (fst $ findLDecl fn m Set.empty))



-- This section provides a method to print the LIR so as to inspect it.

tab :: Int -> String
tab n = concat $ replicate (n*4) " "

addSpace :: String -> String -> String
addSpace a b = a ++ " " ++ b

addNewLine :: Int -> String -> String -> String
addNewLine n a b = a ++ "\n" ++ tab n ++ b



genLDecl :: (Name, LDecl) -> String
genLDecl (n, LConstructor n2 tag arity) = "LDecl " ++ show n ++ " LConstructor " ++ show tag ++" " ++ show arity ++ "\n"
genLDecl (n, LFun opts n2 args e) = "LDecl " ++ show n ++ " LFun " ++"[" ++ (foldr addSpace "" $ map show opts) ++ "]" ++  " [" ++ (foldr addSpace "" $ map show args) ++ "] " ++ "\n" ++ tab 1 ++ genLExp 2 e ++ "\n"

genConst :: Const -> String
genConst (I x) = "I " ++ show x
genConst (BI x) = "BI " ++ show x
genConst (Fl x) = "Fl " ++ show x
genConst (Ch x) = "Ch " ++ show x
genConst (Str x) = "Str " ++ show x
genConst (B8 x) = "B8 " ++ show x
genConst (B16 x) = "B16 " ++ show x
genConst (B32 x) = "B32 " ++ show x
genConst (B64 x) = "B64 " ++ show x
genConst a = show a

genAlt :: Int -> LAlt -> String
genAlt t (LConCase i n args e) = "LConCase " ++ show i ++ " " ++ show n ++ " [" ++ (foldr addSpace "" $ map show args) ++ "] " ++ "\n" ++ tab t ++ genLExp (t+1) e
genAlt t (LConstCase const e) = "LConstCase " ++ genConst const ++ " " ++ "\n" ++ tab t ++ genLExp (t+1) e
genAlt t (LDefaultCase e) = "LDefaultCase " ++ "\n" ++ tab t ++ genLExp (t+1) e

genLExp :: Int -> LExp -> String
genLExp t (LV v) = "LV " ++ show v
genLExp t (LApp b e1 e2) = "LApp " ++ show b ++ " " ++ "\n" ++ tab t ++ genLExp (t+1) e1 ++ " " ++ "[ \n" ++ tab t ++  (foldr (addNewLine t) "" $ map (genLExp (t+1)) e2) ++ " ]"
genLExp t (LLazyApp n e1) = "LLazyApp " ++ show n ++ " " ++ "[ \n" ++ tab t ++ (foldr (addNewLine t) "" $ map (genLExp (t+1)) e1) ++ " ]"
genLExp t (LLazyExp e1) = "LLazyExp " ++ "\n" ++ tab t ++ genLExp (t+1) e1
genLExp t (LForce e1) = "LForce " ++ "\n" ++ tab t ++ genLExp (t+1) e1
genLExp t (LLet n e1 e2) = "LLet " ++ show n ++ " " ++ "\n" ++ tab t ++ genLExp (t+1) e1 ++ " " ++ "\n" ++ tab t ++ genLExp (t+1) e2
genLExp t (LLam args e1 ) = "LLam " ++ " [ " ++ (foldr addSpace "" $ map show args) ++ " ] " ++ "\n" ++ tab t ++ genLExp (t+1) e1
genLExp t (LProj e1 pr) = "LProj " ++ "\n" ++ tab t ++ genLExp (t+1) e1 ++ " " ++ show pr
genLExp t (LCon Nothing i n e) = "LCon " ++ "(Rel: Nothing )" ++ show i ++ " " ++ show n ++ " " ++ "[ \n" ++ tab t ++ (foldr (addNewLine t) "" $ map (genLExp (t+1)) e) ++ " ]"
genLExp t (LCon (Just a) i n e) = "Lcon " ++ "(Rel: Just " ++ show a ++ ") " ++ show i ++ " " ++ show n ++ " " ++ "[ " ++ (foldr addSpace "" $ map (genLExp (t+1)) e) ++ " ]"
genLExp t (LCase c e alt) = "LCase " ++ show c ++ " " ++ "\n" ++ tab t ++ genLExp (t+1) e ++ " " ++ "[ \n" ++ tab t ++ (foldr (addNewLine t) "" $ map (genAlt t) alt) ++ " ]"
genLExp t (LConst c) = "LConst " ++ genConst c
genLExp t (LForeign fd rd e) = "LForeign " ++ show fd ++ " " ++ show rd ++ "[ \n" ++ tab t ++ (foldr (addNewLine t) "" $ map fo e) ++ " ]" where
  fo :: (FDesc,LExp) -> String
  fo (fd, e) = show fd ++ " " ++ "\n" ++ tab t ++ genLExp (t+1) e
genLExp t (LOp pr e) = "LOp " ++ show pr ++ " " ++ "[ \n" ++ tab t ++ (foldr (addNewLine t) "" $ map (genLExp (t+1)) e) ++ " ]"
genLExp t LNothing = "LNothing"
genLExp t (LError str) = "LError " ++ "'" ++ str ++ "'"

-------------------------------------------------------

-- This sections removes any unnecessary declarations LDecl

amap :: (a -> Set Name -> ([b],Set Name)) -> [a] -> Set Name -> ([b],Set Name)
amap f (y : ys) q = let (r,nq) = f y q
                    in let res = amap f ys  nq
                       in (r++ fst res, snd res)
amap f [] q = ([],q)

findLDecl :: LExp -> Map Name LDecl -> Set Name -> ([(Name,LDecl)], Set Name)
findLDecl (LV (Glob n)) m q =  let e = Set.member n q
	                       in case (e) of
			           False -> let mldec = Map.lookup n m
                                            in case (mldec) of
				                 Just ldec -> let (LFun _ _ _ fn) = ldec
				                              in let res1 = findLDecl fn m (Set.insert n q)
							         in ([(n,ldec)] ++ fst res1 , snd res1)
			                         Nothing   -> ([],q)
			           True -> ([],q)
findLDecl (LV (Loc n)) m q = ([],q) 
findLDecl (LApp _ vr lexps) m q= case (vr) of 
                                            (LV (Glob n)) -> let e = Set.member n q
					                     in case (e) of
							          False -> let mldec = Map.lookup n m
                                                                            in case (mldec) of
				                                                 Just ldec -> let (LFun _ _ _ fn) = ldec
										              in let res1 = findLDecl fn m (Set.insert n q)
											      in let res2 = amap (\x q -> findLDecl x m q) lexps (snd res1)
								                                 in ([(n,ldec)] ++ fst res1 ++ fst res2, snd res2)
			                                                         Nothing   -> amap (\x q -> findLDecl x m q) lexps q
			                                          True -> amap (\x q -> findLDecl x m q) lexps q
					    _             -> let res1 = findLDecl vr m q
							     in let res2 = amap (\x q -> findLDecl x m q) lexps (snd res1)
                                                             in (fst res1 ++ fst res2, snd res2)

findLDecl (LLazyApp n lexps) m q = let e = Set.member n q 
                                 in case (e) of 
				    False -> let mldec = Map.lookup n m
                                            in case (mldec) of
		  	                         Just ldec -> let (LFun _ _ _ fn) = ldec
							      in let res1 = findLDecl fn m (Set.insert n q)
							      in let res2 = amap (\x q -> findLDecl x m q) lexps (snd res1)
							         in ([(n,ldec)] ++ fst res1 ++ fst res2, snd res2)
			                         Nothing              -> amap (\x q -> findLDecl x m q) lexps q
				    True  -> amap (\x q -> findLDecl x m q) lexps q
findLDecl (LLazyExp lexp) m q       = findLDecl lexp m q
findLDecl (LForce lexp) m q       = findLDecl lexp m q
findLDecl (LLet _ lexp1 lexp2) m q = let res1 = findLDecl lexp1 m q
                                     in let res2 = findLDecl lexp2 m (snd res1)
				     in (fst res1 ++ fst res2, snd res2)
findLDecl (LLam _ lexp) m q       = findLDecl lexp m q
findLDecl (LProj lexp _) m q      = findLDecl lexp m q
findLDecl (LCon _ _ n lexps) m q  = let e = Set.member n q
                                in case (e) of
				     False -> let mldec = Map.lookup n m
                                             in case (mldec) of
				                  Just ldec -> let res1 = amap (\x q -> findLDecl x m q) lexps (Set.insert n q)
							       in ([(n,ldec)] ++ fst res1 , snd res1)
			                          Nothing   -> amap (\x q -> findLDecl x m q) lexps q
				     True  -> amap (\x q -> findLDecl x m q) lexps q
findLDecl (LCase _ lexp lalts) m q = let res1 = findLDecl lexp m q
                                     in let res2 = amap (\lalt q -> case (lalt) of
                                                                      LDefaultCase lexp        -> findLDecl lexp m q
                                                                      LConstCase _ lexp    -> findLDecl lexp m q
						         	      LConCase _ _ _ lexp      -> findLDecl lexp m q  ) lalts (snd res1)
				        in (fst res1 ++ fst res2, snd res2)
findLDecl (LOp _ lexps) m q  = amap (\x q -> findLDecl x m q) lexps q
findLDecl (LForeign fd1 fd2 fds) m q = amap (\x q -> findLDecl x m q) (map snd fds) q
findLDecl LNothing _ q            = ([],q)
findLDecl _ _ q                   = ([],q)



-------------------------------------------------------

-- This section removes the LNothing arguments. TODO It needs to be fixed. It cannot clean functions that are passed as arguments. ??

filterLN :: LExp -> [LExp] -> ([LExp], [Int])
filterLN arg x = filterLN' 0 arg x where
  filterLN' p arg (y:ys) = let (nle, q) = filterLN' (p+1) arg ys 
                       in case (y==arg) of
                           True   ->   (nle, p:q)
                           False  -> (y:nle, q)
  filterLN' p arg [] = ([],[])

removeArg :: LExp -> LExp -> (LExp, Map Name [Int])
removeArg arg (LApp j1 vr lexps) = let (nlexps,nq) = foldl (\(lle, lq) (le,q) -> (lle ++ [le],  Map.unions [lq, q])) ([],Map.empty) (map (removeArg arg) lexps)
                                        in case (vr) of
                                             LV (Glob n) -> let (rm, li) = filterLN arg nlexps
                                                            in ((LApp j1 vr rm),Map.unions [nq, case (li) of
                                                                                                     [] -> Map.empty 
                                                                                                     _  -> Map.insert n li Map.empty])
                                             _           -> ((LApp j1 vr nlexps),nq)
removeArg arg (LLazyApp n lexps) = let (nlexps,nq) = foldl (\(lle, lq) (le,q) -> (lle ++ [le],  Map.unions [lq, q])) ([],Map.empty) (map (removeArg arg) lexps)
                                    in let (rm, li) = filterLN arg nlexps
                                       in ((LLazyApp n rm),Map.unions [nq, case (li) of
                                                                            [] -> Map.empty 
                                                                            _  -> Map.insert n li Map.empty])
removeArg arg (LLazyExp lexp)       = let (le,q) =  removeArg arg lexp
                                       in ((LLazyExp le), q)
removeArg arg (LForce lexp)       = let (le,q) =  removeArg arg lexp
                                     in ((LForce le), q)
removeArg arg (LLet j1 lexp1 lexp2) = let (le1,q1) =  removeArg arg lexp1
                                       in let (le2,q2) =  removeArg arg lexp2
                                          in ((LLet j1 le1 le2), Map.unions [q1,q2])
removeArg arg (LLam j1 lexp)      = let (le,q) =  removeArg arg lexp
                                     in ((LLam j1 lexp), q)
removeArg arg (LProj lexp j1)      = let (le,q) =  removeArg arg lexp
                                      in ((LProj le j1), q)
removeArg arg (LCon j1 j2 n lexps)  = let (nlexps,nq) = foldl (\(lle, lq) (le,q) -> (lle ++ [le],  Map.unions [lq, q])) ([],Map.empty) (map (removeArg arg) lexps)
                                       in let (rm, li) = filterLN arg nlexps
                                          in ((LCon j1 j2 n rm),Map.unions [nq, case (li) of
                                                                                  [] -> Map.empty 
                                                                                  _  -> Map.insert n li Map.empty])
removeArg arg (LCase j1 lexp lalts) = let (nlalts,nq) = foldl (\(lle, lq) (le,q) -> (lle ++ [le],  Map.unions [lq, q])) ([],Map.empty) (map (\x -> case (x) of 
                                                                                                                                             LDefaultCase lexp        -> let (le,q) = removeArg arg lexp
                                                                                                                                                                         in (LDefaultCase le,q)
                                                                                                                                             LConstCase j2 lexp    -> let (le,q) = removeArg arg lexp
                                                                                                                                                                      in (LConstCase j2 le,q)
                                             	                                                                                             LConCase j3 j4 j5 lexp    -> let (le,q) = removeArg arg lexp
                                                                                                                                                                          in (LConCase j3 j4 j5 le,q)) lalts)
                                       in let (le,q) =  removeArg arg lexp
                                          in ((LCase j1 le nlalts), Map.unions [q,nq])
removeArg arg (LOp j1 lexps)  = let (nlexps,nq) = foldl (\(lle, lq) (le,q) -> (lle ++ [le],  Map.unions [lq, q])) ([],Map.empty) (map (removeArg arg) lexps)
                                 in ((LOp j1 nlexps),nq)
removeArg arg (LForeign fd1 fd2 fds) = let (nfds,nq) = foldl (\(lle, lq) (le,q) -> (lle ++ [le],  Map.unions [lq, q])) ([],Map.empty) (map (\x -> let (le,q) = removeArg arg (snd x) 
                                                                                                                                          in ((fst x,le),q)) fds)
                                        in ((LForeign fd1 fd2 nfds),nq)
removeArg arg le = (le,Map.empty)

cleanFun :: [(Name, [Int])] -> Map Name LDecl -> ([(Name,[Name])],Map Name LDecl)
cleanFun ((n, li):xs) m = let lp = Map.lookup n m
                          in case (lp) of
                              Just (LFun j1 j2 nms j4)  ->     let (rnms,nnms) = apFilter li nms
                                                               in let ldec = ((LFun j1 j2 nnms j4))
                                                                  in let (lrnms,nm) = cleanFun xs (Map.insert n ldec m) 
                                                                     in ((n,rnms):lrnms,nm)  where
                                                                                               apFilter li nms = apFilter' 0 li nms where
                                                                                                        apFilter' p (i:ls) (n:ns) = let (rnms,nnms) = apFilter' (p+1) ls ns
                                                                                                                                    in case (i==p) of
                                                                                                                                         True -> (n:rnms,nnms)
                                                                                                                                         False -> (rnms,n:nnms)
                                                                                                        apFilter' p [] ns = ([],ns) 
                                                                                                        apFilter' p li [] = ([],[])  -- This is only needed because runMain has an LNothing but main does not have a variable.
                              Just (LConstructor _ a t )   -> cleanFun xs (Map.insert n (LConstructor n (a - length li) t) m)
                              _    -> trace (show n) ([],m)
cleanFun [] m = ([],m) 


eraseVarFun :: Map Name LDecl -> Map Name LDecl
eraseVarFun m = let (nm, q) = foldl (\(nm,nq) (n,(ldec,q)) -> (Map.insert n ldec nm, Map.unions [nq,q])) (Map.empty, Map.empty) (Map.toList (Map.map (\ldec -> case (ldec) of
                                                                                                                                                                LFun j1 j2 j3 le -> let (nle,q) = removeArg LNothing le
                                                                                                                                                                                    in (LFun j1 j2 j3 nle, q)
                                                                                                                                                                o                -> (o, Map.empty)                   )  m))   
                in let (ner,nnm) = cleanFun (Map.toList q) nm
                   in eraseVarFun' nnm ner where
                         eraseVarFun' :: Map Name LDecl -> [(Name,[Name])] -> Map Name LDecl
                         eraseVarFun' m ((n,rnms):xs) = let Just ldec = Map.lookup n m
                                                        in let (nldec, lnq) = foldl (\(ldec,pq) rt -> case (ldec) of  
                                                                                                        LFun j1 j2 j3 le -> let (nle,q) = removeArg (LV (Glob rt)) le
                                                                                                                            in (LFun j1 j2 j3 nle, pq ++ [q])
                                                                                                        o                ->  (o, pq)                                   ) (ldec,[]) rnms
                                                           in let (nner, nnnm) =foldl (\(ner,nm) nq -> let (ner',nm') = cleanFun (Map.toList nq) nm
                                                                                                       in  (ner ++ ner',nm')                         ) ([],(Map.insert n nldec m)) lnq
                                                              in eraseVarFun' nnnm (nner ++ xs)
                         eraseVarFun' m []         = m

                                                             

---------------------------------------------------------

-- It creates the tree of dependencies of variables and finds their type.

newtype UniqueId = UnId Int

data OperInfo = Con UniqueId Name Int Int | SApp UniqueId Name Int | LzApp UniqueId Name Int | OLet Name | CaseCon Name Int [Name] | PrimOp UniqueId PrimFn Int

data VarRel = Leaf (OperInfo, Const) | Edge (OperInfo, Name) | EdgeR (Operinfo, UniqueId)   

data FuncCalls = Fun Name [VarRel] | FunCase Name UniqueId [[VarRel]] | FunLzExp Name UniqueId [VarRel]


findVarel :: UniqueId -> LExp -> (([VarRel],UniqueId),[LExp])
findVarel un (LApp j1 vr lexps) = case (vr) of
                               LV (Glob n) -> fst $ foldl (\(((ns,unl),rls),p) lexp -> case (lexp) of
                                                                            LV (Glob nl) -> (((ns ++ [Edge (SApp un n p,nl)],unl),rls), p+1)
                                                                            LConst c     -> (((ns ++ [Leaf (SApp un n p,c)], unl),rls), p+1)
                                                                            _            -> let ((res,nun),nrls) = findVarel unl lexp
                                                                                            in (((ns ++ [EdgeR (SApp un n p,(un+1))] ++ res,nun),nrls ++ rls, p+1)   ) ((([],un+1),[]),0) lexps
                               _           -> ([],un)  -- ?
findVarel un (LLazyApp n lexps) = fst $ foldl (\(((ns,unl),rls),p) lexp -> case (lexp) of
                                                                            LV (Glob nl) -> (((ns ++ [Edge (LzApp un n p,nl)],unl),rls), p+1)
                                                                            LConst c     -> (((ns ++ [Leaf (LzApp un n p,c)], unl),rls), p+1)
                                                                            _            -> let ((res,nun),nrls) = findVarel unl lexp
                                                                                            in (((ns ++ [EdgeR (LzApp un n p,(un+1))] ++ res,nun),rls ++ nrls), p+1)   ) ((([],un+1),[]),0) lexps
findVarel un (LLazyExp lexp)               = (([],un),[LLazyExp lexp]) -- This is probably accompanied by a lets expression, otherwise it would be useless.
findVarel un (LForce lexp)                 = findVarel un lexp -- We will probably need to keep track of this.
findVarel un (LLet j1 lexp1 lexp2)         = let ((r1,nun1),rls1) =  findVarel un lexp1
                                                    in let ((r2,nun2),rls2) =  findVarel nun1 lexp2
                                                       in ((r1 ++ r2 ++ [Res (FCLet j1,lexp1)],nun2),ncn2)
findVarel un (LLam j1 lexp)                = findVarel un lexp  -- TODO ?
findVarel un (LProj lexp j1)               = findVarel un lexp   -- What is Projection? probably lexp is a constructor.
findVarel un (LCon j1 tag n lexps)  = fst $ foldl (\(((ns,un),p) lexp -> case (lexp) of
                                                                        LV (Glob nl) -> (((ns ++ [Edge (Con un n tag p,nl)],un + 1),p+1)
                                                                        LConst c     -> (((ns ++ [Leaf (Con un n tag p,c)], un + 1),p+1)
                                                                        _            -> let ((res,nun),ncn) = findVarel un lexp 
                                                                                        in (((ns ++ [Res (Con nun n tag p, lexp)] ++ res,nun + 1),ncn),p+1)   ) ((([],un),0) lexps
findVarel un (LCase j1 lexp lalts) =  let ((r1,nun1),ncn1) = findVarel un lexp
                                         in let ((r2,nun2),ncn2) = foldl (\((ns,un) x -> case (x) of 
                                                                      LDefaultCase clexp        -> let ((res,nun),ncn) = findVarel un clexp
                                                                                                   in ((ns ++ res,nun),ncn)
                                                                      LConstCasest clexp    -> let ((res,nun),ncn) = findVarel un clexp
                                                                                                  in ((ns ++ res,nun),ncn)
                                             	                      LConCase tag nm args clexp  -> let ((res,nun),ncn) = findVarel un clexp 
                                                                                                     in (((ns ++ [Res (CaseCon nm tag args,lexp)] ++ res),nun),ncn) ) (([],nun1),ncn1 + 1) lalts
                                            in ((r1 ++ r2,nun2),ncn2)
findVarel un (LOp j1 lexps) = foldl (\((ns,un) lexp -> let ((res,nun),ncn) = findVarel un lexp 
                                                              in (((ns ++ res),nun),ncn)           ) (([],un) lexps
findVarel un (LForeign fd1 fd2 fds) = foldl (\((ns,un) x -> let ((res,nun),ncn) = findVarel un (snd x) 
                                                                   in (((ns ++ res),nun),ncn)  ) (([],un) fds 
findVarel un _ = (([],un)


findNextOp :: LExp -> LExp
findNextOp (LApp j1 vr lexps) = case (vr) of
                               LV (Glob n) -> fst $ foldl (\(((ns,unl),rls),p) lexp -> case (lexp) of
                                                                            LV (Glob nl) -> (((ns ++ [Edge (SApp n p,nl)],unl),rls), p+1)
                                                                            LConst c     -> (((ns ++ [Leaf (SApp n p,c)],l),rls), p+1)
                                                                            _            -> let ((res,nun),nrls) = findNextOpl lexp
                                                                                            in (((ns ++ [EdgeR (SApp n p,(un+1))] ++ res,nun),nrls ++ rls, p+1)   ) ((([],un+1),[]),0) lexps
                               _           -> ([],un)  -- ?
findNextOp (LLazyApp n lexps) = fst $ foldl (\(((ns,unl),rls),p) lexp -> case (lexp) of
                                                                            LV (Glob nl) -> (((ns ++ [Edge (LzApp n p,nl)],unl),rls), p+1)
                                                                            LConst c     -> (((ns ++ [Leaf (LzApp n p,c)],l),rls), p+1)
                                                                            _            -> let ((res,nun),nrls) = findNextOpl lexp
                                                                                            in (((ns ++ [EdgeR (LzApp n p,(un+1))] ++ res,nun),rls ++ nrls), p+1)   ) ((([],un+1),[]),0) lexps
findNextOp (LLazyExp lexp)               = (([],un),[LLazyExp lexp]) -- This is probably accompanied by a lets expression, otherwise it would be useless.
findNextOp (LForce lexp)                 = findNextOp lexp -- We will probably need to keep track of this.
findNextOp (LLet j1 lexp1 lexp2)         = let ((r1,nun1),rls1) =  findNextOp lexp1
                                                    in let ((r2,nun2),rls2) =  findNextOp nun1 lexp2
                                                       in ((r1 ++ r2 ++ [Res (FCLet j1,lexp1)],nun2),ncn2)
findNextOp (LLam j1 lexp)                = findNextOp lexp  -- TODO ?
findNextOp (LProj lexp j1)               = findNextOp lexp   -- What is Projection? probably lexp is a constructor.
findNextOp (LCon j1 tag n lexps)  = fst $ foldl (\(((ns,un),p) lexp -> case (lexp) of
                                                                        LV (Glob nl) -> (((ns ++ [Edge (Con n tag p,nl)],un + 1),p+1)
                                                                        LConst c     -> (((ns ++ [Leaf (Con n tag p,c)], + 1),p+1)
                                                                        _            -> let ((res,nun),ncn) = findNextOp lexp 
                                                                                        in (((ns ++ [Res (Con nun n tag p, lexp)] ++ res,nun + 1),ncn),p+1)   ) ((([],un),0) lexps
findNextOp (LCase j1 lexp lalts) =  let ((r1,nun1),ncn1) = findNextOp lexp
                                         in let ((r2,nun2),ncn2) = foldl (\((ns,un) x -> case (x) of 
                                                                      LDefaultCase clexp        -> let ((res,nun),ncn) = findNextOp clexp
                                                                                                   in ((ns ++ res,nun),ncn)
                                                                      LConstCasest clexp    -> let ((res,nun),ncn) = findNextOp clexp
                                                                                                  in ((ns ++ res,nun),ncn)
                                             	                      LConCase tag nm args clexp  -> let ((res,nun),ncn) = findNextOp clexp 
                                                                                                     in (((ns ++ [Res (CaseCon nm tag args,lexp)] ++ res),nun),ncn) ) (([],nun1),ncn1 + 1) lalts
                                            in ((r1 ++ r2,nun2),ncn2)
findNextOp (LOp j1 lexps) = foldl (\((ns,un) lexp -> let ((res,nun),ncn) = findNextOp lexp 
                                                              in (((ns ++ res),nun),ncn)           ) (([],un) lexps
findNextOp (LForeign fd1 fd2 fds) = foldl (\((ns,un) x -> let ((res,nun),ncn) = findNextOp (snd x) 
                                                                   in (((ns ++ res),nun),ncn)  ) (([],un) fds 
findNextOp _ = (([],un)


-- First int fo Con SApp and LzApp is used to distinguish between application of the same name inside the same function.
-- First int of Con is its tag.
--newtype ExOrder = ExOrd [(Int)]
--newtype UniqueId = UnId Int
--data FCName = Con ExOrder UniqueId Name Int Int | SApp ExOrder UniqueId Name Int | LzApp ExOrder UniqueId Name Int | FCLet ExOrder Name | CaseCon ExOrder Name Int [Name]

-- Here the relation is that of equality.
--data VarRel = Leaf (FCName, Const) | Edge (FCName, Name) | Res (FCName, LExp)




-- findVarel :: UniqueId -> ExOrder -> LExp -> (([VarRel],UniqueId),ExOrder)
-- findVarel un cn (LApp j1 vr lexps) = case (vr) of
--                                     LV (Glob n) -> fst $ foldl (\(((ns,un),cn),p) lexp -> case (lexp) of
--                                                                                  LV (Glob nl) -> (((ns ++ [Edge (SApp (cn ++ ((last cn) + 1))  un n p,nl)],un + 1),cn), p+1)
--                                                                                  LConst c     -> (((ns ++ [Leaf (SApp (cn ++ ((last cn) + 1)) un n p,c)], un + 1),cn), p+1)
--                                                                                  _            -> let ((res,nun),ncn) = findVarel un (cn ++ ((last cn) + 1)) lexp
--                                                                                                  in (((ns ++ [Res (SApp (cn ++ ((last cn) + 1)) un n p,lexp)] ++ res,nun+1),ncn), p+1)   ) ((([],un),cn),0) lexps
--                                     _           -> (([],un),cn)  -- ?
-- findVarel un cn (LLazyApp n lexps) = fst $ foldl (\(((ns,un),cn),p) lexp -> case (lexp) of
--                                                                         LV (Glob nl) -> (((ns ++ [Edge (LzApp un n p,nl)],un+1),cn), p+1)
--                                                                         LConst c     -> (((ns ++ [Leaf (LzApp un n p,c)],un+1),cn), p+1)
--                                                                         _            -> let ((res,nun),ncn) = findVarel un cn lexp  
--                                                                                         in (((ns ++ [Res (LzApp nun n p,lexp)] ++ res, nun + 1),ncn), p+1)   ) ((([],un),cn),0) lexps
-- findVarel un cn (LLazyExp lexp)               = findVarel un cn lexp
-- findVarel un cn (LForce lexp)                 = findVarel un cn lexp
-- findVarel un cn (LLet j1 lexp1 lexp2)         = let ((r1,nun1),ncn1) =  findVarel un cn lexp1
--                                                     in let ((r2,nun2),ncn2) =  findVarel nun1 ncn1 lexp2
--                                                        in ((r1 ++ r2 ++ [Res (FCLet j1,lexp1)],nun2),ncn2)
-- findVarel un cn (LLam j1 lexp)                = findVarel un cn lexp  -- TODO ?
-- findVarel un cn (LProj lexp j1)               = findVarel un cn lexp   -- What is Projection? probably lexp is a constructor.
-- findVarel un cn (LCon j1 tag n lexps)  = fst $ foldl (\(((ns,un),cn),p) lexp -> case (lexp) of
--                                                                         LV (Glob nl) -> (((ns ++ [Edge (Con un n tag p,nl)],un + 1),cn),p+1)
--                                                                         LConst c     -> (((ns ++ [Leaf (Con un n tag p,c)], un + 1),cn),p+1)
--                                                                         _            -> let ((res,nun),ncn) = findVarel un cn lexp 
--                                                                                         in (((ns ++ [Res (Con nun n tag p, lexp)] ++ res,nun + 1),ncn),p+1)   ) ((([],un),cn),0) lexps
-- findVarel un cn (LCase j1 lexp lalts) =  let ((r1,nun1),ncn1) = findVarel un cn lexp
--                                          in let ((r2,nun2),ncn2) = foldl (\((ns,un),cn) x -> case (x) of 
--                                                                       LDefaultCase clexp        -> let ((res,nun),ncn) = findVarel un cn clexp
--                                                                                                    in ((ns ++ res,nun),ncn)
--                                                                       LConstCase cnst clexp    -> let ((res,nun),ncn) = findVarel un cn clexp
--                                                                                                   in ((ns ++ res,nun),ncn)
--                                              	                      LConCase tag nm args clexp  -> let ((res,nun),ncn) = findVarel un cn clexp 
--                                                                                                      in (((ns ++ [Res (CaseCon nm tag args,lexp)] ++ res),nun),ncn) ) (([],nun1),ncn1 + 1) lalts
--                                             in ((r1 ++ r2,nun2),ncn2)
-- findVarel un cn (LOp j1 lexps) = foldl (\((ns,un),cn) lexp -> let ((res,nun),ncn) = findVarel un cn lexp 
--                                                               in (((ns ++ res),nun),ncn)           ) (([],un),cn) lexps
-- findVarel un cn (LForeign fd1 fd2 fds) = foldl (\((ns,un),cn) x -> let ((res,nun),ncn) = findVarel un cn (snd x) 
--                                                                    in (((ns ++ res),nun),ncn)  ) (([],un),cn) fds 
-- findVarel un cn _ = (([],un),cn)



-- Here the result consists of Constructors with consts as their variables.
-- findTypes: LExp -> [Lexp]
-- findTypes (LV (Glob n)) =  let e = Set.member n q
-- findTypes (LV (Loc n)) = ([],q) 
-- findTypes (LApp _ vr lexps)= case (vr) of 
-- findTypes (LLazyApp n lexps) = let e = Set.member n q 
-- findTypes (LLazyExp lexp)       = findTypes lexp
-- findTypes (LForce lexp)       = findTypes lexp
-- findTypes (LLet _ lexp1 lexp2) = let res1 = findTypes lexp1
-- findTypes (LLam _ lexp)       = findTypes lexp
-- findTypes (LProj lexp _)      = findTypes lexp
-- findTypes (LCon _ _ n lexps)  = let e = Set.member n q
-- findTypes (LCase _ lexp lalts) = let res1 = findTypes lexp
-- findTypes (LOp _ lexps)  = amap (\x q -> findTypes x) lexps q
-- findTypes (LForeign fd1 fd2 fds) = amap (\x q -> findTypes x) (map snd fds) q
-- findTypes LNothing _ q            = ([],q)
-- findTypes _ _ q                   = ([],q)


-- data RLExp = Top | Leaf RLExp [LExp] | Node RLExp [RLExp]
-- 
-- reverseLExp :: RLExp -> LExp -> RLExp
-- reverseLExp r (LApp j1 vr lexps) = let par = (Parent r (LApp j1 vr [LNothing]))
--                                    in foldl (++) [] (map (reverseLExp par) lexps)
-- reverseLExp r (LLazyApp n lexps) = let par = Parent r (LLazyApp n [LNothing])
--                                    in foldl (++) [] (map (reverseLExp par) lexps)
-- reverseLExp r (LLazyExp lexp)               = reverseLExp (Parent r (LLazyExp LNothing)) lexp
-- reverseLExp r (LForce lexp)                 = reverseLExp (Parent r (LForce LNothing)) lexp
-- reverseLExp r (LLet j1 lexp1 lexp2)         = let r1 =  reverseLExp (Parent r (LLet j1 LNothing LNothing)) lexp1
--                                               in let r2 =   reverseLExp (Parent r (LLet j1 LNothing LNothing)) lexp2
--                                                  in r1 ++ r2
-- reverseLExp r (LLam j1 lexp)                = reverseLExp (Parent r (LLam j1 LNothing)) lexp
-- reverseLExp r (LProj lexp j1)               = reverseLExp (Parent r (LProj LNothing j1)) lexp   -- What is Projection? probably lexp is a constructor.
-- reverseLExp r (LCon j1 j2 n lexps)  = let par = Parent r (LCon j1 j2 n [LNothing])
--                                       in foldl (++) [] (map (reverseLExp par) lexps)
-- reverseLExp r (LCase j1 lexp lalts) = foldl (\ns x -> case (x) of 
--                                                            LDefaultCase lexp        -> let par = Parent r (LCase j1 LNothing [LDefaultCase LNothing])
--                                                                                        in ns ++ reverseLExp par lexp
--                                                            LConstCase j2 lexp    -> let par = Parent r (LCase j1 LNothing [LConstCase j2 LNothing])
--                                                                                        in ns ++ reverseLExp par lexp
--                                              	           LConCase j3 j4 j5 lexp  -> let par = Parent r (LCase j1 LNothing [LConCase j3 j4 j5 LNothing])
--                                                                                        in ns ++ reverseLExp par lexp ) [] lalts
-- reverseLExp r (LOp j1 lexps) = let par = (Parent r (LOp j1 [LNothing]))
--                                in foldl (++) [] (map (reverseLExp par) lexps)
-- reverseLExp r (LForeign fd1 fd2 fds) = let par = (Parent r (LForeign fd1 fd2 (map (\(x,y) -> (x,LNothing)) fds)))
--                                        in foldl (++) [] (map (reverseLExp par) (map snd fds))
-- reverseLExp r _ = []
-- 

--findOutNoApp :: LExp -> Const
