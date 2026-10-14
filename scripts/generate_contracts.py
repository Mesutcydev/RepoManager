#!/usr/bin/env python3
"""Generate human/machine contracts from the built Swift tool catalog.
Run RepoManagerCatalog first; no network, credentials or reference-repo access.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
catalog = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert len(catalog) == len({x['name'] for x in catalog})
docs = ROOT / 'Docs'
(docs / 'tool-catalog.json').write_text(json.dumps({'version': 1, 'tools': catalog}, indent=2) + '\n')
lines = ['# Built-in tool and permission catalog', '',
         'Generated from the compiled Swift catalog. Arguments use the exact schemas in [tool-catalog.json](tool-catalog.json).', '',
         'Read tools require selected-scope authorization. Local edits require Act. All remote writes require an immutable native review. Consequential/destructive writes also require owner authentication and specific confirmation; delete/transfer require the full repository name. Secret write tools are native-only and never exposed to model or agent execution.', '',
         'Permissions below are coarse repository roles; GitHub also enforces endpoint-specific App/PAT permissions, organization approval and feature availability. Scope/identity/permissions/remote state are revalidated before a write. An accepted asynchronous operation is not a completion receipt.', '']
for group in sorted({x['group'] for x in catalog}):
    lines += ['## ' + group, '', '| Tool | Risk | Role | Native only | External agents | Route / operation |', '| --- | --- | --- | --- | --- | --- |']
    for t in (x for x in catalog if x['group'] == group):
        route = t['method'] + ' ' + (t['path'] or 'local')
        lines.append(f"| `{t['name']}` | {t['risk']} | {t['permission']} | {'Yes' if t['nativeOnly'] else 'No'} | {'Granted scope only' if t['externalAgents'] else 'Unavailable'} | `{route}` |")
    lines += ['']
lines += ['## Schema and execution limits', '', 'Unknown properties are rejected. Strings, arrays, numbers, enums and object nesting are bounded. Paths/refs/SHA/entity segments receive semantic validation in addition to schema validation. Secrets are entered in secure fields, sealed to GitHub public keys and excluded from tool context/output. Tool reviews expire after five minutes and cannot be approved by voice/API.', '',
          'Draft: 30 changed files / 2 MiB snapshots. Text file: 256 KiB. Range: 200 lines. New repository attachment: 1 MiB. Tool steps: 25 with a repository, five otherwise. Artifacts/release assets: 50 MiB in encrypted bounded chunks. Searches/logs/maps disclose coverage/truncation.', '']
(docs / 'TOOL_CATALOG.md').write_text('\n'.join(lines))

def obj(properties, required=(), **extra):
    return {'type': 'object', 'properties': properties, 'required': list(required), 'additionalProperties': False, **extra}
def ref(name): return {'$ref': '#/components/schemas/' + name}
def array(items): return {'type': 'array', 'items': items}
string = {'type': 'string'}
uuid = {'type': 'string', 'format': 'uuid'}
any_json = {}
reasoning = {'type': 'string', 'enum': ['automatic','off','none','minimal','low','medium','high','xhigh','max']}
schemas = {
    'Error': obj({'error': obj({'type': string, 'message': string}, ['type','message'])}, ['error']),
    'RepositoryScope': obj({'accountID': {'type':'integer'}, 'connectionID': uuid, 'repositoryID': {'type':'integer'}, 'owner': string, 'name': string, 'branch': string}, ['accountID','connectionID','repositoryID','owner','name','branch']),
    'ToolDefinition': obj({'name': string, 'group': string, 'description': string, 'risk': {'type':'string','enum':['read','localEdit','mutation','consequential','destructive']}, 'permission': {'type':'string','enum':['pull','push','admin']}, 'method':string,'path':string,'reviewPath':string,'schema':any_json,'nativeOnly':{'type':'boolean'}}, ['name','group','description','risk','permission','method','path','schema','nativeOnly']),
    'ToolInvocation': obj({'name': {'type':'string','maxLength':100}, 'arguments':any_json}, ['name','arguments']),
    'ToolOutcome': obj({'id':string,'name':string,'status':{'type':'string','enum':['running','success','failure','cancelled','approval']},'detail':string,'approvalID':uuid}, ['id','name','status','detail']),
    'AgentSessionRequest': obj({'model': {'type':'string','description':'profile UUID/model ID'}, 'mode': {'type':'string','enum':['plan','act'],'default':'plan'}}, ['model']),
    'AgentSession': obj({'id':uuid,'owner':uuid,'providerID':uuid,'model':string,'repository':ref('RepositoryScope'),'mode':{'type':'string','enum':['plan','act']},'created':{'type':'number','description':'Unix seconds'}}, ['id','owner','providerID','model','mode','created']),
    'Message': {'type':'object','properties':{'role':{'type':'string','enum':['system','user','assistant','tool']},'content':{'oneOf':[string,array(any_json)]},'tool_calls':array(any_json),'tool_call_id':string},'required':['role'],'additionalProperties':False,'description':'Text and structured client-owned tool calls/results only. Images/audio/unknown content blocks are unsupported.'},
    'RunRequest': obj({'messages': {'type':'array','items':ref('Message'),'maxItems':500},'reasoning':obj({'effort':reasoning,'summary':{'type':'string','enum':['auto','concise','detailed']}}),'reasoning_effort':reasoning}, ['messages']),
    'RunSnapshot': obj({'id':uuid,'owner':uuid,'sessionID':uuid,'state':string,'text':string,'reasoning':string,'tools':array(ref('ToolOutcome')),'usage':any_json,'error':string,'created':{'type':'number','description':'Unix seconds'}}, ['id','owner','sessionID','state','text','reasoning','tools','created']),
    'CapabilitySummary': obj({'version':{'const':1},'https':{'const':True},'text':{'const':True},'tools':{'const':True},'native_approval_required':{'const':True},'local_runtimes':{'const':False},'history_access':{'const':False}}, ['version','https','text','tools','native_approval_required','local_runtimes','history_access']),
    'ModelMetadata': {'type':'object','properties':{'id':string,'contextTokens':{'type':'integer'},'outputTokens':{'type':'integer'},'inputCostPerMillion':{'type':'number'},'outputCostPerMillion':{'type':'number'},'reasoning':any_json,'availability':string,'format':{'type':'string','enum':['responses','chatCompletions','anthropic','gemini']}},'required':['id'],'description':'Absent usage/limits/pricing are unknown, not zero.'},
    'ModelList': {'type':'object','properties':{'object':{'const':'list'},'data':array(any_json),'models':array(any_json)}},
    'CompatibilityRequest': obj({'model':string,'messages':array(ref('Message')),'input':{'oneOf':[string,array(any_json)]},'instructions':string,'system':string,'prompt':string,'stream':{'type':'boolean','default':False},'max_tokens':{'type':'integer','minimum':1,'maximum':4096},'max_output_tokens':{'type':'integer','minimum':1,'maximum':4096},'tools':array(any_json),'tool_choice':{'const':'auto'},'store':{'const':False},'reasoning':obj({'effort':reasoning,'summary':{'type':'string','enum':['auto','concise','detailed']}}),'reasoning_effort':reasoning,'thinking':obj({'type':{'type':'string','enum':['adaptive','enabled','disabled']}}, ['type']),'output_config':obj({'effort':reasoning})}, ['model']),
    'NativeReview': {'type':'object','properties':{'id':uuid,'scope':ref('RepositoryScope'),'operation':string,'risk':string,'arguments':any_json,'before':any_json,'expires':{'type':'number','description':'Unix seconds'},'approval':{'const':'native_only'},'changes':array(any_json)},'required':['id','scope','operation','risk','arguments','before','expires','approval','changes'],'description':'Inspection only. There is no approval POST route. Secrets are names/status only.'},
    'OperationReceipt': {'type':'object','properties':{'id':uuid,'conversationID':uuid,'scope':ref('RepositoryScope'),'operation':string,'state':{'type':'string','enum':['approved','executing','accepted','completed','failed','uncertain','cancelled']},'result':any_json,'date':{'type':'number','description':'Unix seconds'},'reviewedArguments':any_json,'reviewedBefore':any_json,'expectedHead':string},'required':['id','conversationID','scope','operation','state','result','date'],'description':'202 acceptance and ambiguous writes remain distinct from verified completion.'},
}
paths = {}
errors = {str(code): {'description':desc,'content':{'application/json':{'schema':ref('Error')}}} for code,desc in [(400,'Invalid or unsupported request'),(401,'Authentication required'),(403,'Grant/ownership/policy denied'),(409,'Conflict, changed idempotency payload or stale review'),(429,'Authentication/request throttled')]}
session_param = {'name':'sessionID','in':'path','required':True,'schema':uuid}
run_param = {'name':'runID','in':'path','required':True,'schema':uuid}
def route(path, method, summary, response_schema=any_json, body=None, status=200, stream=False, idem=False):
    op = {'operationId':method+'_'+path.strip('/').replace('/','_').replace('{','').replace('}',''), 'summary':summary, 'security':[{'clientBearer':[]}], 'responses':{str(status):{'description':'Success','content':{'application/json':{'schema':response_schema}}}, **errors}}
    params=[]
    if '{sessionID}' in path: params.append(session_param)
    if '{runID}' in path: params.append(run_param)
    if idem: params.append({'name':'Idempotency-Key','in':'header','schema':{'type':'string','maxLength':200},'description':'Same client/session/key and identical body returns the existing run; changed body is 409. Session-scoped and cleared when listener stops.'})
    if params: op['parameters']=params
    if body: op['requestBody']={'required':True,'content':{'application/json':{'schema':body}},'description':'Maximum 1 MiB body'}
    if stream:
        op['responses'][str(status)]['content'].update({'text/event-stream':{'schema':{'type':'string','description':'SSE events; explicit cancellation/error/finish. No native approval event grants approval.'}},'application/x-ndjson':{'schema':{'type':'string','description':'Ollama text routes only'}}})
    paths.setdefault(path,{})[method]=op
route('/v1/capabilities','get','Authenticated capability summary',ref('CapabilitySummary'))
for p in ['/v1/models','/api/tags']: route(p,'get','Granted provider models and metadata',ref('ModelList'))
route('/api/show','post','Granted model metadata',any_json,obj({'model':string},['model']))
route('/api/version','get','Compatibility server version',obj({'version':string,'local_runtimes':{'const':False}},['version','local_runtimes']))
route('/api/ps','get','No imported local runtimes',obj({'models':{'type':'array','maxItems':0,'items':any_json}},['models']))
for p in ['/v1/chat/completions','/v1/responses','/v1/messages','/api/chat','/api/generate']:
    route(p,'post','Text compatibility; client-owned tools returned without app execution',any_json,ref('CompatibilityRequest'),stream=True)
route('/v1/agent/sessions','post','Create client-owned explicitly granted session',ref('AgentSession'),ref('AgentSessionRequest'),201)
root='/v1/agent/sessions/{sessionID}'
route(root+'/tools','get','Permitted built-in schemas',array(ref('ToolDefinition')))
route(root+'/tools/execute','post','Execute scoped built-in tool; mutations prepare native reviews',ref('ToolOutcome'),ref('ToolInvocation'),idem=True)
route(root+'/approvals','get','Inspect pending reviews; approval remains native-only',array(ref('NativeReview')))
route(root+'/operations','get','Inspect session operation receipts',array(ref('OperationReceipt')))
route(root+'/runs','post','Start a bounded app-agent run',ref('RunSnapshot'),ref('RunRequest'),202,idem=True)
route(root+'/runs/{runID}','get','Inspect owned run',ref('RunSnapshot'))
route(root+'/runs/{runID}/cancel','post','Cancel owned run and invalidate reviews',obj({'cancelled':{'const':True}},['cancelled']))
route(root+'/runs/{runID}/events','get','Replay and stream owned run events',any_json,stream=True)
contract={'openapi':'3.1.0','info':{'title':'Repo Manager external-agent API','version':'1.0.0','description':'Opt-in HTTPS on 11435. Native-scoped bearer clients. No existing-chat access, remote approval, vision/audio/embeddings/classifiers, shell or imported runtimes. Compatibility is a bounded subset; unknown options fail explicitly. All date numbers are Unix seconds. Native mutation review is required.'},'servers':[{'url':'https://{host}:11435','variables':{'host':{'default':'localhost','description':'Use configured certificate hostname/IP; trust exported public certificate, never disable verification.'}}}],'security':[{'clientBearer':[]}],'paths':paths,'components':{'securitySchemes':{'clientBearer':{'type':'http','scheme':'bearer','description':'One-time native-paired UUID.secret, kept in client protected storage; never put in URLs.'}},'schemas':schemas}}
(docs/'openapi.json').write_text(json.dumps(contract,indent=2)+'\n')
print(f'Generated {len(catalog)} tools and {sum(len(x) for x in paths.values())} routes.')
