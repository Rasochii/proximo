/// Política de novas tentativas dos providers do app: nenhuma.
///
/// O Riverpod 3 refaz sozinho um provider que falha, e enquanto tenta o estado fica "carregando":
/// a tela de erro nunca aparece. Aqui isso não ajuda. Os streams do Firestore já reconectam por
/// conta própria, então quando emitem erro (permissão negada, documento fora do formato) repetir
/// não resolve; e as callables têm retry próprio no `QueueFunctionsApi`. Cada tela mostra o erro
/// com "Tentar de novo".
///
/// Usada no `ProviderScope` do app e no dos testes, para os dois se comportarem igual.
Duration? noAutomaticRetry(int retryCount, Object error) => null;
