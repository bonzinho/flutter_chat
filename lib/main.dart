import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

void main() async{
  runApp(MyApp());
}

final ThemeData kIOSTheme = ThemeData(
  primarySwatch: Colors.orange,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = ThemeData(
  primarySwatch: Colors.purple,
  accentColor: Colors.orangeAccent[400],
);

final googleSignIn = GoogleSignIn();
final auth = FirebaseAuth.instance;

// certificar que o utilizador está logado
Future<Null> _ensureLoggedIn() async{
  GoogleSignInAccount user = googleSignIn.currentUser;
  if(user == null)
    user = await googleSignIn.signInSilently(); // tentar fazer o login sem ser necessário informar as credenciais
  if(user == null)
    user = await googleSignIn.signIn();
  if(await auth.currentUser() == null){ // veriica se esta logado no google e no firebase
    GoogleSignInAuthentication credentials = await googleSignIn.currentUser.authentication; // acesso as credenciais
    await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken
    );
  }
}

_handleSubmitted(String text) async{
  await _ensureLoggedIn();
  _sendMessage(text: text);
}

void _sendMessage({String text, String imgUrl}){
  Firestore.instance.collection("messages").add(
    {
      "text": text,
      "imgUrl": imgUrl,
      "senderName": googleSignIn.currentUser.displayName,
      "senderPhotoUrl": googleSignIn.currentUser.photoUrl,
    }
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chat for my friends",
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context).platform == TargetPlatform.iOS ?
      kIOSTheme: kDefaultTheme,
      home: ChatScreen(),
    );
  }
}


class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {

  @override
  Widget build(BuildContext context) {
    return SafeArea( // permite que seja ignoradoo note do iphone
      bottom: false,
      top: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Chat for Friends"),
          centerTitle: true,
          elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0, //define como é visto o elevation no android / Ios para isso usar semote o theme.of(context.platfrm)
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: StreamBuilder( // vai ter um listerner para sempque que haja alterações refazer os dados
                stream: Firestore.instance.collection("messages").snapshots(), // verifica se existe alguam alteração
                  builder: (context, snapshot){
                    switch(snapshot.connectionState){
                      // Caso não exista conexão ou esteja à espera aparece o loading
                      case ConnectionState.none:
                      case ConnectionState.waiting:
                        return Center(
                          child: CircularProgressIndicator(),
                        );
                      default:
                        return ListView.builder(
                            // Lista reversa
                            reverse: true,
                            itemCount: snapshot.data.documents.length,
                            itemBuilder: (context, index){
                              List r = snapshot.data.documents.reversed.toList(); // inverte a lista original, assim as ultimas mensgens aparecem em baixo
                              return ChatMessage(r[index].data);
                            }
                        );
                    }
                  }
              ),
            ),
            Divider(
              height: 1,
            ),
            Container(
              decoration: BoxDecoration(
                color:Theme.of(context).cardColor, // Especificar a cor default da plataforma
              ),
              child: TextComposer(),
            )
          ],
        ),
      ),
    );
  }
}

class TextComposer extends StatefulWidget {
  @override
  _TextComposerState createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {

  final _textController = TextEditingController();
  bool _isComposing = false;

  void _reset(){
    _textController.clear();
    setState(() {
      _isComposing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconTheme( // definir um esquema de cores apenas apra este widget, para isso especificamo um theme
      data: IconThemeData(color: Theme.of(context).accentColor), // Todos os filhos deste widget terãoa cor accent color
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0), // funciona identico o padding do css, margem apra dentro do widget, usamos um const , isto faz com que o app seja mais leve, pois ele já sabe que este valor não vai mudar
        decoration: Theme.of(context).platform == TargetPlatform.iOS ?
          BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey[200]))
          ) : null,
        child: Row(
          children: <Widget>[
            Container(
              child: IconButton(
                  icon: Icon(Icons.photo_camera),
                  onPressed: () async{
                    // enviar imagens no chat
                    await _ensureLoggedIn();
                    File imgFile = await ImagePicker.pickImage(source: ImageSource.camera);
                    if(imgFile == null) return;

                    //upload da imagem para o firestorae
                    StorageUploadTask task = FirebaseStorage.instance.ref()
                        // .child('photos') // sistema de pastas
                        .child(googleSignIn.currentUser.id.toString() + DateTime.now().millisecondsSinceEpoch.toString()).putFile(imgFile);

                    StorageTaskSnapshot taskSnapshot = await task.onComplete;
                    String url = await taskSnapshot.ref.getDownloadURL();
                    _sendMessage(imgUrl: url);
                  }
              ),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration.collapsed(hintText: "Enviar mensagem"),
                onChanged: (text){
                  setState(() {
                    _isComposing = text.length > 0; // verifica se está a ser esrito alguam coisa, se estiver muda a variavel para true
                  });
                },
                onSubmitted: (text){
                  _handleSubmitted(text);
                  _reset();
                }, // faz com que o texto seja enviado a carregar no enter do teclado
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? CupertinoButton(
                  child: Text("Enviar"),
                  onPressed: _isComposing ? (){
                    _handleSubmitted(_textController.text);
                    _reset();

                  } : null,
                )
                  : IconButton(
                    icon: Icon(Icons.send),
                    onPressed: _isComposing ? (){
                      _handleSubmitted(_textController.text);
                      _reset();
                    } : null,
                  )
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {

  final Map<String, dynamic> data;

  ChatMessage(this.data);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundImage: NetworkImage(data["senderPhotoUrl"]),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(data["senderName"],
                  style: Theme.of(context).textTheme.subhead,
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  child: data["imgUrl"] != null ?
                      Image.network(data["imgUrl"], width: 250) :
                      Text(data["text"])
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}



