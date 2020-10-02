const axios = require('axios');
const xml2js = require('xml2js');
const fs = require('fs');
const path = require('path');
const util = require('util');
const exec = util.promisify(require('child_process').exec);

let data;
let auth;
let token;
let modules;
async function computeModules() {
  
    // Read modules from the parent pom.xml
    const parentJs = await xml2js.parseStringPromise(fs.readFileSync(`pom.xml`, 'utf8'));
    modules = parentJs.project.modules[0].module.filter(m => !/shared/.test(m));
}

async function getRequest(module, pageNumber){
	module =  module.replace("-parent","");
	await timeout(10000);
	
	url='https://api.github.com/repos/vaadin/'+module+'/issues?state=open&page='+pageNumber;
	let res = await axios.get(url, {
		headers: {
			'User-Agent': 'vaadin-transfer',
			'Authorization': 'token '+ token
		}
	});
	
	//let res = await run("curl -u "+auth+" "+url);
	data = res.data;
	//console.log(data);
	return data
} 

function timeout(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function run(cmd) {
    const { stdout, stderr } = await exec(cmd);
    return stdout;
}

async function main(){
	await computeModules();
	
	if (process.argv.length = 3) {
		auth = process.argv[2];
		token = auth.split(":").pop();
    }

	console.log("Generating a script to transfer the tickets");
	console.log("Checking the transferTicket.sh file");

	for(j=0;j<modules.length;j++){
		console.log("Collecting the ticket in "+modules[j].replace("-parent",""));
		page = 1;
		clone = "git clone git@github.com:vaadin/"+modules[j].replace("-parent","")+".git";
		str1 = "cd " + modules[j].replace("-parent","");
		repoName = modules[j].replace("-flow-parent","");
		fileName = "transferTicket.sh";
		//fileName = "transferTicket/"+repoName +"_"+fileName;
		fs.appendFileSync(fileName, clone+"\n" + str1+"\n");
		do {
			data = await getRequest(modules[j], page);
			//console.log(data);
			if(data.length!=0){
				
				for (i=0; i<data.length;i++){
					if(!data[i].pull_request){
						if(repoName === 'vaadin-iron-list'){
						    repoName = 'vaadin-flow-components';
						}
						str = "/opt/agent/temp/buildTmp/hub/bin/hub issue transfer "+data[i].number+" "+repoName+" > result.txt\n";
						transNumber="number=$(grep 'issues' result.txt | cut -d'/' -f7)\n"
                
						labelString = '"'+ modules[j].replace("-parent","")+ '"';
						data[i].labels.forEach(label=>{
							labelString+= ',"'+label.name+'"';
						})
				
						transLabel='curl -u '+ auth +' -H "Content-Type: application/json" -X POST -d '+"'"+'{"labels":['+labelString+']}'+"' https://api.github.com/repos/vaadin/"+repoName+"/issues/$number/labels"
						removeResult='rm -rf result.txt\n'
						sleepTime = 'sleep 2s\n'
						fs.appendFileSync(fileName, str+transNumber+transLabel+"\n"+removeResult);
					}
				}
				page++;
			} 
		}while(data.length!=0);
		str2 = "cd ..";
		fs.appendFileSync(fileName, str2+"\n");
	}
}

main();