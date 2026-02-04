
import xml.etree.ElementTree as ET

namespaces = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}

def extract_text(xml_file):
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        content = []
        for p in root.findall('.//w:p', namespaces):
            para_text = []
            for t in p.findall('.//w:t', namespaces):
                if t.text:
                    para_text.append(t.text)
            content.append(''.join(para_text))
            
        return '\n'.join(content)
    except Exception as e:
        return str(e)

if __name__ == "__main__":
    print(extract_text("document.xml"))
